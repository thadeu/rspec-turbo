# frozen_string_literal: true

# Opt-in slow-test profiler, loaded into each worker by Worker.spawn.
#
# Enable with RSPEC_PROFILE_SLOW=1 to print, at the end of the run:
#   - Top 20 slowest / query-heaviest examples
#   - TOP 15 FILES BY TIME  (parsed back by RSpecTurbo::Display for the report)
#
# Optional thresholds:
#   RSPEC_PROFILE_THRESHOLD_TIME=0.2    # seconds; example must exceed to list
#   RSPEC_PROFILE_THRESHOLD_QUERIES=30  # SQL queries; same idea
#
# Optional folder grouping:
#   RSPEC_PROFILE_GROUP_BY=1
#     Auto-detects the base from the rspec CLI args. Running `rspec
#     spec/requests/v1` buckets examples by direct subfolder of that base.
#     With multiple paths it uses their longest common directory.
#   RSPEC_PROFILE_GROUP_BY=spec/requests/v1
#     Explicit base path. Buckets by direct subfolder of that base.
#   RSPEC_PROFILE_GROUP_BY=spec/requests/v1/items,spec/requests/v1/bins
#     Explicit list of folders; each is its own bucket.
#
# Query counting relies on ActiveSupport::Notifications, so this block only
# does work in a Rails app and only when explicitly enabled.

return unless ENV["RSPEC_PROFILE_SLOW"] || ENV["RSPEC_PROFILE_GROUP_BY"]

RSpec.configure do |config|
  slow_tests = []
  file_times = Hash.new(0.0)
  file_query_counts = Hash.new(0)
  folder_times = Hash.new(0.0)
  folder_query_counts = Hash.new(0)
  folder_example_counts = Hash.new(0)

  threshold_time = Float(ENV["RSPEC_PROFILE_THRESHOLD_TIME"] || "0.2")
  threshold_queries = Integer(ENV["RSPEC_PROFILE_THRESHOLD_QUERIES"] || "30")

  blank = ->(str) { str.nil? || str.strip.empty? }

  # Resolve grouping config from env into one of:
  #   { mode: :subfolder, base: "spec/requests/v1" }  - bucket by direct subfolder
  #   { mode: :list, bases: ["spec/foo", "spec/bar"] } - each folder is its own bucket
  resolve_group_by = lambda do |raw|
    next nil if blank.call(raw)

    raw = raw.delete_suffix("/")

    if raw.include?(",")
      bases = raw.split(",").map { |p| p.strip.delete_prefix("./").delete_suffix("/") }.reject(&:empty?)
      next nil if bases.empty?

      next {mode: :list, bases: bases}
    end

    if ["1", "true", "auto"].include?(raw.downcase)
      cli_paths = RSpec.configuration.files_to_run
      next nil if cli_paths.empty?

      dirs = cli_paths.map do |path|
        cleaned = path.delete_prefix("./").sub(/:\d+\z/, "")
        File.directory?(cleaned) ? cleaned : File.dirname(cleaned)
      end.uniq

      base =
        if dirs.size == 1
          dirs.first
        else
          parts = dirs.map { |d| d.split("/") }
          common = []
          parts.first.each_with_index do |segment, i|
            break unless parts.all? { |p| p[i] == segment }

            common << segment
          end
          common.empty? ? nil : common.join("/")
        end

      next nil if base.nil?

      next {mode: :subfolder, base: base}
    end

    {mode: :subfolder, base: raw}
  end

  bucket_for = lambda do |file_path, group_config|
    next nil unless group_config

    normalized = file_path.to_s.delete_prefix("./")

    case group_config[:mode]
    when :subfolder
      base = group_config[:base]
      next nil unless normalized.start_with?("#{base}/")

      rest = normalized[(base.length + 1)..]
      first = rest.split("/").first
      first ? "#{base}/#{first}" : nil
    when :list
      group_config[:bases].find { |b| normalized.start_with?("#{b}/") || normalized == b }
    end
  end

  group_config = nil

  config.before(:suite) do
    group_config = resolve_group_by.call(ENV["RSPEC_PROFILE_GROUP_BY"])
  end

  # Query counting needs ActiveSupport; without it (non-Rails suites) we still
  # profile by time and just report zero queries instead of crashing.
  count_sql = defined?(ActiveSupport::Notifications)

  config.around(:each) do |example|
    query_count = 0
    subscriber =
      if count_sql
        ActiveSupport::Notifications.subscribe("sql.active_record") do |_, _, _, _, payload|
          next if payload[:name] == "SCHEMA"
          next if /\A\s*(SAVEPOINT|RELEASE|ROLLBACK|BEGIN|COMMIT)/i.match?(payload[:sql])

          query_count += 1
        end
      end

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    example.run
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber

    file = example.metadata[:file_path]
    file_times[file] += duration
    file_query_counts[file] += query_count

    if group_config
      folder_key = bucket_for.call(file, group_config)

      if folder_key
        folder_times[folder_key] += duration
        folder_query_counts[folder_key] += query_count
        folder_example_counts[folder_key] += 1
      end
    end

    next unless duration >= threshold_time || query_count >= threshold_queries

    slow_tests << {
      description: example.full_description,
      duration: duration,
      queries: query_count,
      file: file
    }
  end

  config.after(:suite) do
    puts
    puts
    puts "#{"\e[34m=" * 96}\e[0m"
    puts " \e[34mSLOW / EXPENSIVE EXAMPLES (time >= #{threshold_time}s OR queries >= #{threshold_queries})\e[0m"
    puts "#{"\e[34m=" * 96}\e[0m"

    puts "TIME     QUERIES FILE                                                         EXAMPLE"

    slow_tests.sort_by { |t| -t[:duration] }.first(20).each do |t|
      puts format(
        "%6.3fs %4d     %-60s %s",
        t[:duration],
        t[:queries],
        t[:file].to_s.sub(%r{^\./}, "").slice(0, 60),
        t[:description].slice(0, 80)
      )
    end

    puts
    puts "#{"\e[31m=" * 96}\e[0m"
    puts " \e[31mTOP 15 FILES BY TIME\e[0m"
    puts "#{"\e[31m=" * 96}\e[0m"

    puts "TIME     QUERIES  FILE"

    file_times.sort_by { |_, t| -t }.first(15).each do |file, time|
      puts format("%6.2fs %6d    %s", time, file_query_counts[file], file.to_s.sub(%r{^\./}, ""))
    end

    if group_config && folder_times.size > 1
      label =
        case group_config[:mode]
        when :subfolder then "FOLDERS UNDER #{group_config[:base]} BY TIME"
        when :list then "FOLDERS BY TIME"
        end

      puts
      puts "#{"\e[33m=" * 96}\e[0m"
      puts " \e[33m#{label}\e[0m"
      puts "#{"\e[33m=" * 96}\e[0m"

      puts "TIME     QUERIES  EXAMPLES FOLDER"

      folder_times.sort_by { |_, t| -t }.each do |folder, time|
        puts format("%6.2fs %6d    %4d      %s", time, folder_query_counts[folder], folder_example_counts[folder], folder)
      end
    end

    puts
  end
end
