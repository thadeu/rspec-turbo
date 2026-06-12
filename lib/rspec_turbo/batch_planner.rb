# frozen_string_literal: true

require "json"

module RSpecTurbo
  # Runs `rspec --dry-run --format json` to count examples per file, then packs
  # the files into N balanced batches using the Longest-Processing-Time first
  # (LPT) greedy heuristic. Files heavier than a single batch's fair share are
  # split into slices of individual example IDs so one huge file can't bottle-
  # neck a worker.
  #
  # If the dry-run fails for any reason it falls back to equal-weight packing.
  class BatchPlanner
    attr_reader :counts, :batches, :pending_count, :dry_run_elapsed

    def initialize(files, num_workers:, rspec_options: [])
      @files = files
      @n = num_workers
      @rspec_options = rspec_options
      @counts = {}
      @batches = []
      @pending_count = 0
      @dry_run_elapsed = 0
    end

    def plan!
      result = dry_run
      @counts = result[:counts]
      @pending_count = result[:pending_count]
      units = build_units(@files, @counts, result[:ids])
      @batches = bin_pack(units)

      self
    end

    def example_count(units) = units.sum { |unit| unit_weight(unit) }

    private

    def dry_run
      return empty_result if @files.empty?

      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      raw = capture_dry_run
      @dry_run_elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0).round

      json_start = raw.index("{")
      raise "No JSON in dry-run output" unless json_start

      parse_examples(JSON.parse(raw[json_start..]))
    rescue => e
      warn "  ⚠ dry-run failed (#{e.message}) — using equal-weight distribution"
      log_dry_run_error

      empty_result
    end

    def capture_dry_run
      File.open(Config.dry_run_log, "w") do |err_file|
        IO.popen(
          # COVERAGE=0 keeps SimpleCov from contaminating the JSON on stdout.
          [{"COVERAGE" => "0", "TEST_ENV_NUMBER" => "1"},
            "bundle", "exec", "rspec", "--dry-run", "--format", "json",
            *@rspec_options, *@files.map { |f| "spec/#{f}" }],
          err: err_file, &:read
        )
      end
    end

    def parse_examples(parsed)
      counts = Hash.new(0)
      ids = Hash.new { |hash, key| hash[key] = [] }

      parsed["examples"].each do |example|
        file = example["file_path"].delete_prefix("./spec/")
        counts[file] += 1
        ids[file] << example["id"]
      end

      {counts: counts, ids: ids, pending_count: parsed.dig("summary", "pending_count").to_i}
    end

    def empty_result = {counts: {}, ids: {}, pending_count: 0}

    def log_dry_run_error
      return unless File.exist?(Config.dry_run_log)

      last_err = File.readlines(Config.dry_run_log).last(10).join.strip
      warn "  Dry-run stderr:\n#{last_err}" unless last_err.empty?
    end

    def unit_weight(unit) = unit.is_a?(Array) ? unit.size : (@counts[unit] || 1)

    # A "unit" is either a whole file (a String) or a slice of example IDs
    # (an Array) carved out of a file too heavy to fit in one batch.
    def build_units(files, counts, ids)
      total = files.sum { |f| counts[f] || 1 }
      threshold = [(total.to_f / @n).ceil, 1].max

      files.flat_map do |file|
        file_ids = ids[file].to_a

        if (counts[file] || 1) > threshold && file_ids.size > 1
          file_ids.each_slice(threshold).to_a
        else
          [file]
        end
      end
    end

    def bin_pack(units)
      n = [@n, units.size].min

      return [units] if n <= 1

      buckets = Array.new(n) { [0, []] }

      units.sort_by { |unit| -unit_weight(unit) }.each do |unit|
        bucket = buckets.min_by { |total, _| total }
        bucket[1] << unit
        bucket[0] += unit_weight(unit)
      end

      buckets.reject { |_, packed| packed.empty? }.map { |_, packed| packed }
    end
  end
end
