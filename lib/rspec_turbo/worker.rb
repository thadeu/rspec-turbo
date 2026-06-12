# frozen_string_literal: true

require "fileutils"

module RSpecTurbo
  # A single RSpec process running one batch of work. Worker.spawn forks the
  # process and returns a Worker the executor tracks until the process exits.
  #
  # Every worker is wired with two helper files shipped by the gem:
  #   * progress_reporter.rb — a formatter that streams the example count to a
  #     progress file so the parent can draw a global progress bar.
  #   * slow_profile.rb      — an opt-in profiler (RSPEC_PROFILE_SLOW=1) that
  #     emits the "TOP N FILES BY TIME" block the report aggregates. It is a
  #     no-op when profiling is disabled, so requiring it is always safe.
  class Worker
    PROGRESS_REPORTER_PATH = File.expand_path("progress_reporter.rb", __dir__)
    SLOW_PROFILE_PATH = File.expand_path("slow_profile.rb", __dir__)

    attr_reader :pid, :label, :units, :slot, :started, :progress_file

    def self.spawn(label:, units:, slot:, rspec_options:)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      progress_file = Config.progress_path(slot)
      File.write(progress_file, "0")

      pid = Process.spawn(
        env(slot, progress_file),
        "bundle", "exec", "rspec", "--color", "--order", "random",
        "--require", PROGRESS_REPORTER_PATH,
        "--require", SLOW_PROFILE_PATH,
        "--format", "progress",
        "--format", "RSpecTurbo::ProgressReporter",
        *junit_args(slot),
        *rspec_options, *rspec_args(units),
        out: Config.log_path(label), err: [:child, :out]
      )

      new(pid: pid, label: label, units: units, slot: slot, started: started, progress_file: progress_file)
    end

    def self.env(slot, progress_file)
      {
        # Force the test env so each worker connects to the *_test database
        # DbSetup created, regardless of how the run was launched (a Rake/Rails
        # task boots in development) or whether rails_helper sets it.
        "RAILS_ENV" => "test",
        "TEST_ENV_NUMBER" => slot.to_s,
        "RSPEC_TURBO_PROGRESS_FILE" => progress_file,
        "COVERAGE" => ENV.fetch("COVERAGE", "0")
      }.merge(profile_env)
    end

    # Profiling is on by default: turbo flips RSPEC_PROFILE_SLOW=1 in the child
    # unless the user set it themselves. RSPEC_TURBO_NO_PROFILE=1 hard-unsets the
    # profiler envs in the child (nil = unset), winning over any inherited value.
    def self.profile_env
      return {"RSPEC_PROFILE_SLOW" => nil, "RSPEC_PROFILE_GROUP_BY" => nil} unless Config.profile?

      {"RSPEC_PROFILE_SLOW" => ENV.fetch("RSPEC_PROFILE_SLOW", "1")}
    end

    # A unit is either a file path (String) or a pre-resolved list of example
    # IDs (Array) — the latter is already in `spec/...[1:2]` form.
    def self.rspec_args(units)
      units.flat_map { |unit| unit.is_a?(Array) ? unit : ["spec/#{unit}"] }
    end

    def self.junit_args(slot)
      dir = Config.junit_dir
      return [] unless dir

      FileUtils.mkdir_p(dir)

      ["--require", "rspec_junit_formatter",
        "--format", "RspecJunitFormatter",
        "--out", File.join(dir, "rspec-turbo-#{slot}.xml")]
    end

    private_class_method :env, :profile_env, :rspec_args, :junit_args

    def initialize(pid:, label:, units:, slot:, started:, progress_file:)
      @pid = pid
      @label = label
      @units = units
      @slot = slot
      @started = started
      @progress_file = progress_file
    end

    def duration = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started).round
  end
end
