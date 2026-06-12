# frozen_string_literal: true

require "fileutils"

module RSpecTurbo
  # Top-level orchestration: parse argv, set up the test databases, discover
  # and plan the spec files, hand execution to the Executor, then print the
  # report and (optionally) merge coverage. Exits non-zero on any failure.
  class Runner
    def initialize(argv)
      @options = Options.new(argv)
      @workers = Config.workers
    end

    def run
      FileUtils.mkdir_p(Config.log_dir)
      print_header

      setup_databases
      planner = plan(discover_files)

      FileUtils.rm_rf("coverage") if Config.coverage?

      display = Display.new(planner)
      executor = Executor.new(planner, display, @options.rspec_options)
      results = executor.run
      wall_total = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - executor.wall_started).round

      display.print_report(results, wall_total, @workers)
      merge_coverage if Config.coverage?

      exit((results.any? { |r| r[:status] == "FAIL" }) ? 1 : 0)
    end

    private

    def print_header
      puts
      puts Terminal::SEP_THICK
      puts "  RSpec Turbo - Parallel"
      puts Terminal::SEP_THICK
      puts
    end

    def setup_databases
      setup = DbSetup.new(@workers)
      cached = !Config.force_setup? && setup.cached?
      label = cached ? "DB cache hit" : "Setting up #{@workers} test DB(s)"

      ok, elapsed = with_spinner(label) { setup.run! }

      unless ok
        print "\e[?25h" if Config::TTY
        warn "✗ DB setup failed."
        exit 2
      end

      puts "  #{Terminal.c("32", "✓")} #{@workers} DB(s) ready (#{Terminal.fmt_duration(elapsed)})"
    end

    def discover_files
      files = FileDiscovery.new(@options.folders, exclude_patterns: @options.exclude_patterns).files

      if files.empty?
        puts "Nothing to run."
        exit 0
      end

      files
    end

    def plan(files)
      planner = nil

      _, elapsed = with_spinner("Counting examples (#{files.size} files)") do
        planner = BatchPlanner.new(files, num_workers: @workers, rspec_options: @options.rspec_options).plan!
      end

      total = planner.counts.values.sum
      avg = planner.batches.empty? ? 0 : (total.to_f / planner.batches.size).round
      pending_str = planner.pending_count.positive? ? " · #{planner.pending_count} pending" : ""

      puts "  #{Terminal.c("32", "✓")} #{total} examples#{pending_str} · #{files.size} files · " \
           "#{planner.batches.size} batches (~#{avg} each) (#{Terminal.fmt_duration(elapsed)})"
      puts

      planner
    end

    def merge_coverage
      puts
      print "  Merging coverage reports..."
      $stdout.flush

      merge_log = Config.coverage_merge_log
      ok = system("RAILS_ENV=test bundle exec rake coverage:merge", out: merge_log, err: [:child, :out])

      if ok
        puts " #{Terminal.c("32", "✓")} done"
      else
        puts " #{Terminal.c("31", "✗")} failed (run `rake coverage:merge` manually)"
        last_lines = File.exist?(merge_log) ? File.readlines(merge_log).last(10).join.strip : ""
        warn last_lines unless last_lines.empty?
      end
    end

    # Animated single-line spinner wrapping a block. On a TTY it shows a
    # spinning animation and clears it on completion; on CI it just runs the
    # block. Returns [block_result, elapsed_seconds].
    def with_spinner(label)
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      unless Config::TTY
        result = yield

        return [result, (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0).round]
      end

      frame = 0
      running = true
      print "\e[?25l"

      thread = Thread.new do
        while running
          spin = Terminal::SPINNER_FRAMES[frame % Terminal::SPINNER_FRAMES.size]
          print "\r  \e[36m#{spin}\e[0m #{label}..."
          $stdout.flush
          sleep 0.1
          frame += 1
        end
      end

      result = yield
      running = false
      thread.join
      elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0).round
      print "\r\e[2K"
      print "\e[?25h"

      [result, elapsed]
    end
  end
end
