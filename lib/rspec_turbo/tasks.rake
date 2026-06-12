# frozen_string_literal: true

require "rspec_turbo"

namespace :spec do
  desc "Run the full RSpec suite in parallel with rspec-turbo"
  task :turbo do
    # Runs the whole suite; the runner spawns its own per-worker rspec
    # processes (so this task needs no :environment) and exits with the
    # suite's status. For specific folders or flags, use `rspec-turbo` directly.
    RSpecTurbo::Runner.new([]).run
  end
end

namespace :coverage do
  # Merge the per-worker SimpleCov result files into one report. Workers run
  # with their own TEST_ENV_NUMBER, so each writes a separate .resultset.json
  # (point them at coverage/$TEST_ENV_NUMBER/ in spec_helper — see the README).
  # Invoked automatically by the runner when COVERAGE=1.
  desc "Merge per-worker SimpleCov results (JSON on CI, HTML locally)"
  task :merge do
    begin
      require "simplecov"
      require "simplecov_json_formatter"
    rescue LoadError => e
      abort "coverage:merge needs `simplecov` and `simplecov_json_formatter` in your Gemfile — #{e.message}"
    end

    pattern = ENV.fetch("RSPEC_TURBO_COVERAGE_GLOB", "coverage/**/.resultset.json")
    result_files = Dir[pattern]

    if result_files.empty?
      warn "coverage:merge: no result files matched #{pattern.inspect} — nothing to merge"
      next
    end

    on_ci = %w[1 true].include?(ENV["CI"].to_s.downcase)
    chosen_formatter = on_ci ? SimpleCov::Formatter::JSONFormatter : SimpleCov::Formatter::HTMLFormatter

    puts "Merging #{result_files.size} coverage result file(s) → #{chosen_formatter}"

    SimpleCov.collate(result_files) do
      formatter chosen_formatter
    end
  end
end
