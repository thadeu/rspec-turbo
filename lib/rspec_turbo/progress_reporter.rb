# frozen_string_literal: true

require "rspec/core"
require "rspec/core/formatters/base_formatter"

module RSpecTurbo
  # RSpec formatter loaded inside each worker process. Its only job is to write
  # the running example count to RSPEC_TURBO_PROGRESS_FILE after every example,
  # so the parent runner can sum the slots and draw a live progress bar.
  #
  # Deliberately self-contained (no dependency on the rest of the gem) so it can
  # be required by absolute path inside the spawned `rspec` process. The slowest
  # files report is produced separately by slow_profile.rb.
  class ProgressReporter < RSpec::Core::Formatters::BaseFormatter
    # Register the three terminal notifications (exactly one fires per example)
    # instead of :example_finished, which older rspec-core versions don't
    # dispatch to formatters — that left the counter stuck at zero on some
    # projects. This mirrors the built-in progress formatter.
    RSpec::Core::Formatters.register self, :example_passed, :example_failed, :example_pending

    def initialize(output)
      super
      @count = 0
      @progress_file = ENV["RSPEC_TURBO_PROGRESS_FILE"]
    end

    def example_passed(_notification)
      record
    end

    def example_failed(_notification)
      record
    end

    def example_pending(_notification)
      record
    end

    private

    def record
      @count += 1
      return unless @progress_file

      File.write(@progress_file, @count.to_s)
    rescue
      nil
    end
  end
end
