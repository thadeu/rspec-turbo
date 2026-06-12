# frozen_string_literal: true

require_relative "rspec_turbo/version"
require_relative "rspec_turbo/config"
require_relative "rspec_turbo/terminal"
require_relative "rspec_turbo/options"
require_relative "rspec_turbo/db_setup"
require_relative "rspec_turbo/file_discovery"
require_relative "rspec_turbo/batch_planner"
require_relative "rspec_turbo/display"
require_relative "rspec_turbo/worker"
require_relative "rspec_turbo/executor"
require_relative "rspec_turbo/runner"

# Parallel RSpec runner with smart, dry-run-based example balancing.
#
# progress_reporter.rb and slow_profile.rb are intentionally NOT required here:
# they run inside the spawned worker processes (loaded by absolute path), not in
# the orchestrator, so the parent never has to load rspec-core or ActiveSupport.
module RSpecTurbo
end

# In a Rails app, register the `spec:turbo` Rake task (also reachable as
# `rails spec:turbo`). Skipped entirely when Rails isn't loaded.
require_relative "rspec_turbo/railtie" if defined?(Rails::Railtie)
