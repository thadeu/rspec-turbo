# frozen_string_literal: true

module RSpecTurbo
  # Splits the raw ARGV into RSpec options and target folders/files, and pulls
  # out --exclude-pattern values for the file discovery step.
  #
  # The tricky part is knowing which flags consume the next token as a value
  # (so it is not mistaken for a folder); OPTIONS_WITH_VALUES lists those.
  class Options
    OPTIONS_WITH_VALUES = Set.new(%w[
      --exclude-pattern --pattern --format --require --order --seed
      --tag --failure-exit-code --backtrace-exclusion-pattern
    ]).freeze

    attr_reader :rspec_options, :folders, :exclude_patterns

    def initialize(argv)
      @rspec_options, @folders = parse(argv)
      @exclude_patterns = extract_exclude_patterns(@rspec_options)
    end

    private

    def parse(argv)
      options = []
      folders = []
      i = 0

      while i < argv.length
        arg = argv[i]

        unless arg.start_with?("-")
          folders << arg
          i += 1
          next
        end

        options << arg

        if takes_value?(arg, argv[i + 1])
          options << argv[i + 1]
          i += 2
        else
          i += 1
        end
      end

      [options, folders]
    end

    def takes_value?(arg, next_arg)
      !arg.include?("=") &&
        OPTIONS_WITH_VALUES.include?(arg.split("=").first) &&
        next_arg && !next_arg.start_with?("-")
    end

    def extract_exclude_patterns(options)
      patterns = []

      options.each_with_index do |opt, idx|
        if opt.start_with?("--exclude-pattern=")
          patterns << opt.delete_prefix("--exclude-pattern=")
        elsif opt == "--exclude-pattern"
          patterns << options[idx + 1] if options[idx + 1]
        end
      end

      patterns
    end
  end
end
