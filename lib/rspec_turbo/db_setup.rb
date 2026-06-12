# frozen_string_literal: true

require "digest"
require "fileutils"

module RSpecTurbo
  # Ensures N test databases exist, one per worker slot, by spawning a Rails
  # db setup process per slot (each with its own TEST_ENV_NUMBER).
  #
  # The result is cached by a fingerprint of db/schema.rb + db/seeds.rb plus
  # the worker count, so repeat runs skip setup entirely. Set
  # RSPEC_TURBO_FORCE_SETUP=1 to force recreation.
  class DbSetup
    FINGERPRINT_FILES = ["db/schema.rb", "db/seeds.rb"].freeze
    SETUP_COMMAND = ["bundle", "exec", "rails", "db:drop", "db:create", "db:schema:load", "db:seed"].freeze

    def initialize(num_workers, force: Config.force_setup?)
      @n = num_workers
      @force = force
    end

    def run!
      return true if !@force && cached?

      FileUtils.mkdir_p(Config.log_dir)
      failed = wait_all(spawn_all)

      return write_marker && true if failed.empty?

      failed.each { |worker| show_log(worker) }
      false
    end

    def cached? = File.exist?(marker_path)

    private

    def spawn_all
      (1..@n).map do |slot|
        log = Config.setup_log_path(slot)
        pid = Process.spawn(
          {"TEST_ENV_NUMBER" => slot.to_s, "RAILS_ENV" => "test"},
          *SETUP_COMMAND,
          out: log, err: [:child, :out]
        )

        {pid: pid, slot: slot, log: log}
      end
    end

    def wait_all(workers)
      workers.filter_map do |worker|
        _, status = Process.waitpid2(worker[:pid])

        status.success? ? nil : worker
      end
    end

    def show_log(worker)
      return unless File.exist?(worker[:log])

      warn "\n── slot #{worker[:slot]} output ──"
      warn File.read(worker[:log]).lines.last(15).join
    end

    def write_marker
      FileUtils.mkdir_p(Config.setup_marker_dir)
      FileUtils.touch(marker_path)
    end

    def marker_path
      File.join(Config.setup_marker_dir, "slots-#{@n}-schema-#{schema_fingerprint}")
    end

    def schema_fingerprint
      digest = Digest::SHA256.new

      FINGERPRINT_FILES.each do |path|
        digest.update(path)
        digest.update(File.exist?(path) ? File.read(path) : "")
      end

      digest.hexdigest[0, 12]
    end
  end
end
