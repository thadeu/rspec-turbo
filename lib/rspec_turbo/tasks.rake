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
