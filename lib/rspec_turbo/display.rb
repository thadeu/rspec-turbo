# frozen_string_literal: true

module RSpecTurbo
  # Owns every line printed to the terminal: the live per-worker spinner
  # (TTY), the plain CI worker roster, and the final report — failures plus
  # the slowest folders/files (fed by slow_profile.rb in each worker log).
  class Display
    def initialize(planner)
      @planner = planner
    end

    # Folder label string for a batch's units, e.g. "models · requests".
    def self.folder_labels(batch_units, with_counts: false, max_len: nil)
      counts = Hash.new(0)
      batch_units.each { |unit| counts[folder_for(unit)] += 1 }
      label = counts.map { |folder, n| with_counts ? "#{folder}(#{n})" : folder }.join(" · ")

      return label unless max_len

      label.slice(0, max_len).then { |slice| (slice.length < label.length) ? "#{slice}…" : slice }
    end

    def self.folder_for(unit)
      path = unit.is_a?(Array) ? unit.first.split("[").first.delete_prefix("./spec/") : unit
      parts = path.split("/")

      return parts[0] if parts.size <= 1 || parts[1].end_with?("_spec.rb")

      "#{parts[0]}/#{parts[1]}"
    end

    def print_plan
      total = @planner.counts.values.sum

      puts
      puts "  Found #{@planner.batches.flatten.size} spec files (#{total} examples) → #{@planner.batches.size} batches"
      puts

      @planner.batches.each_with_index do |batch, i|
        label = format("worker/%02d", i + 1)
        folders = Display.folder_labels(batch)

        puts format("  %-10s  %3d files  ~%-4d ex   %s", label, batch.size, @planner.example_count(batch), folders)
      end

      puts
    end

    def print_report(results, wall_total, n_workers)
      sum_total = results.sum { |r| r[:duration] }
      speedup = sum_total.positive? ? (sum_total.to_f / wall_total).round(2) : 0
      total_ex = results.sum { |r| @planner.example_count(r[:units]) }
      file_data = parse_profiler_data(results.map { |r| Config.log_path(r[:label]) })
      failed = results.select { |r| r[:status] == "FAIL" }

      puts
      puts Terminal::SEP_THICK
      puts "  RSpec Turbo Report"
      puts Terminal::SEP_THICK

      # On a TTY you watch failures scroll by live, so show them first. In CI
      # the log is read top-to-bottom afterwards, so push failures to the very
      # end where they sit right above the one-line summary — easy to find.
      if Config::TTY
        print_failures(failed)
        print_slowest(file_data)
      else
        print_slowest(file_data)
        print_failures(failed)
      end

      print_summary(failed, total_ex, wall_total, sum_total, speedup, n_workers)
    end

    # Consolidated, sorted PASS/FAIL roster — printed once after every worker
    # finishes (CI path) so the per-worker results form one clean block.
    def print_worker_summary(results)
      return if results.empty?

      puts
      puts Terminal::SEP_THICK
      puts "  Workers"
      puts Terminal::SEP_THICK
      puts

      results.sort_by { |r| r[:label] }.each do |r|
        icon = (r[:status] == "PASS") ? "✓" : "✗"
        code = (r[:status] == "PASS") ? "32" : "31"
        line = format("#{icon} %-10s  %-7s  %-6s   %s",
          r[:label], Terminal.fmt_duration(r[:duration]), r[:status], Display.folder_labels(r[:units]))

        puts Terminal.c(code, line)
      end
    end

    def spinner_line(state, frame)
      folders = Display.folder_labels(state[:units], max_len: 55)

      case state[:status]
      when :pending
        "  \e[90m○ #{state[:label]}\e[0m"
      when :running
        elapsed = state[:started] ? (Process.clock_gettime(Process::CLOCK_MONOTONIC) - state[:started]).round : 0
        spin = Terminal::SPINNER_FRAMES[frame % Terminal::SPINNER_FRAMES.size]
        total = @planner.example_count(state[:units])

        "  \e[36m#{spin} #{state[:label]}\e[0m  ~#{total} ex  #{Terminal.fmt_duration(elapsed)}   #{folders}"
      when :done
        color = (state[:result] == "PASS") ? "\e[32m" : "\e[31m"
        icon = (state[:result] == "PASS") ? "✓" : "✗"

        "  #{color}#{icon} #{state[:label]}  #{Terminal.fmt_duration(state[:duration])}  #{state[:result]}   #{folders}\e[0m"
      end
    end

    private

    def print_summary(failed, total_ex, wall_total, sum_total, speedup, n_workers)
      pending_count = @planner.pending_count
      pass_fail = failed.empty? ? Terminal.c("32", "✓ All passed") : Terminal.c("31", "✗ #{failed.size} failed")
      wall_str = Terminal.c("33", format("wall %-7s", Terminal.fmt_duration(wall_total)))
      sum_str = Terminal.c("90", "sum #{Terminal.fmt_duration(sum_total)}")
      spd_str = Terminal.c("1", "#{speedup}x")
      pending_str = pending_count.positive? ? "  ·  #{Terminal.c("33", "#{pending_count} pending")}" : ""

      puts
      puts "  #{pass_fail}  ·  #{total_ex} examples#{pending_str}  ·  #{n_workers} workers  ·  #{wall_str}  #{sum_str}  #{spd_str}"
      puts
      puts Terminal::SEP_THICK
    end

    def print_failures(failed)
      return if failed.empty?

      puts "  #{Terminal.c("31", "✗ #{failed.size} worker(s) failed: #{failed.map { |r| r[:label] }.join(", ")}")}"

      failed.each do |r|
        content = clean_log(Config.log_path(r[:label]))
        next unless content

        puts
        puts Terminal.c("31", Terminal::SEP_THIN)
        puts Terminal.c("31", "  Failures in #{r[:label]}")
        puts Terminal.c("31", Terminal::SEP_THIN)
        puts extract_failures(content)
      end

      puts "  #{Terminal::SEP_THIN}"
    end

    def extract_failures(content)
      start = content.index("\nFailures:\n") ||
        content.index("\nAn error occurred while loading") ||
        content.index("\nFailed examples:")

      return content.lines.last(30).join.strip unless start

      finish = content.index("\nFinished in") ||
        content.index(/\nTop \d/) ||
        content.length

      content[start...finish].strip
    end

    def print_slowest(file_data)
      return if file_data.empty?

      puts "  #{Terminal.c("1", "Slowest folders")}  #{Terminal.c("90", "↳ optimize these first")}"
      puts

      folder_times = aggregate_by_folder(file_data)
      max_s = folder_times.first&.last.to_f

      folder_times.first(8).each do |folder, seconds|
        bar_width = max_s.positive? ? [(seconds / max_s * 20).round, 1].max : 1

        puts format("  %-45s  %6s  %s", folder, Terminal.fmt_duration(seconds.round), slowest_bar(bar_width))
      end

      puts "  #{Terminal::SEP_THIN}"
      puts "  #{Terminal.c("1", "Slowest files")}"
      puts

      file_data.sort_by { |e| -e[:seconds] }.first(5).each do |e|
        puts format("  %-60s  %s", e[:file].delete_prefix("spec/"), Terminal.fmt_duration(e[:seconds].round))
      end

      puts "  #{Terminal::SEP_THIN}"
    end

    def slowest_bar(width)
      return "#{"#" * width}#{"." * (20 - width)}" unless Config::TTY

      "\e[37m#{"▓" * width}\e[90m#{"░" * (20 - width)}\e[0m"
    end

    # Parse "TOP N FILES BY TIME" sections (emitted by slow_profile.rb) from
    # every worker log and flatten them into [{seconds:, file:}].
    def parse_profiler_data(log_files)
      log_files.filter_map { |log| clean_log(log) }.flat_map do |content|
        section = content[/TOP \d+ FILES BY TIME.*?(?=\n\n|\z)/m]
        next [] unless section

        section.each_line.filter_map do |line|
          m = line.match(%r{^\s*([\d.]+)s\s+\d+\s+(spec/.+)$})
          m && {seconds: m[1].to_f, file: m[2].strip}
        end
      end
    end

    # Aggregate file times by their immediate parent folder (relative to spec/).
    def aggregate_by_folder(file_data)
      sums = Hash.new(0.0)

      file_data.each do |e|
        parts = e[:file].delete_prefix("spec/").split("/")
        folder = (parts.size > 1) ? parts[0..-2].join("/") : parts[0]
        sums[folder] += e[:seconds]
      end

      sums.sort_by { |_, seconds| -seconds }
    end

    # Read a worker log, scrub invalid bytes and strip ANSI colour codes.
    def clean_log(path)
      return nil unless File.exist?(path)

      Terminal.strip_ansi(File.binread(path).force_encoding("UTF-8").scrub)
    end
  end
end
