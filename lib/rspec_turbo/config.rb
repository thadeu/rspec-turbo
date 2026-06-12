# frozen_string_literal: true

require "etc"

module RSpecTurbo
  # Central place for environment-driven settings and derived log paths.
  #
  # All tuning happens through environment variables so the runner stays a
  # single zero-config binary:
  #
  #   RSPEC_TURBO_MAX               number of parallel workers (default: nproc)
  #   RSPEC_TURBO_LOG_DIR           where per-worker logs live
  #   RSPEC_TURBO_FORCE_SETUP=1     recreate test DBs even if cached
  #   RSPEC_TURBO_PROGRESS_INTERVAL seconds between CI progress lines
  #   COVERAGE=1                    merge SimpleCov results after the run
  #   JUNIT_DIR=path                emit JUnit XML per worker into this dir
  #
  # Slow-test profiling is opt-in and feeds the "Slowest folders/files" report
  # (see slow_profile.rb): RSPEC_PROFILE_SLOW=1, RSPEC_PROFILE_GROUP_BY, etc.
  module Config
    module_function

    TTY = $stdout.tty? && !ENV["CI"]

    def tty? = TTY

    def workers
      Integer(ENV.fetch("RSPEC_TURBO_MAX") { ENV.fetch("RSPEC_PARALLEL_MAX", Etc.nprocessors) })
    end

    def force_setup?
      flag = ENV["RSPEC_TURBO_FORCE_SETUP"] || ENV["RSPEC_PARALLEL_FORCE_SETUP"]

      %w[1 true yes].include?(flag.to_s.downcase)
    end

    def progress_interval = Integer(ENV.fetch("RSPEC_TURBO_PROGRESS_INTERVAL", "30"))

    def coverage? = %w[1 true].include?(ENV.fetch("COVERAGE", "0").downcase)

    def junit_dir = ENV["JUNIT_DIR"]

    # Slow-test profiling is on by default; RSPEC_TURBO_NO_PROFILE=1 is the
    # master kill switch. See slow_profile.rb and Worker.profile_env.
    def profile? = !%w[1 true yes].include?(ENV["RSPEC_TURBO_NO_PROFILE"].to_s.downcase)

    # ── Derived paths ──────────────────────────────────────────────────────

    def log_dir = ENV.fetch("RSPEC_TURBO_LOG_DIR") { ENV.fetch("RSPEC_LOG_DIR", "tmp/rspec-turbo") }

    def setup_marker_dir = File.join(log_dir, "setup")

    def log_path(label) = File.join(log_dir, "#{label.tr("/", "_")}.log")

    def progress_path(slot) = File.join(log_dir, "progress_#{slot}.txt")

    def setup_log_path(slot) = File.join(log_dir, "setup_slot#{slot}.log")

    def dry_run_log = File.join(log_dir, "dry_run_stderr.log")

    def coverage_merge_log = File.join(log_dir, "coverage_merge.log")
  end
end
