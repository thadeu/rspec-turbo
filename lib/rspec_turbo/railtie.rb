# frozen_string_literal: true

require "rails/railtie"

module RSpecTurbo
  # Registers the `spec:turbo` Rake task in host Rails apps, so the suite can be
  # launched via `rake spec:turbo` or `rails spec:turbo` (Rails routes unknown
  # commands to Rake) in addition to the `rspec-turbo` binary.
  #
  # Only loaded when Rails is present (see the guard in lib/rspec_turbo.rb).
  class Railtie < Rails::Railtie
    rake_tasks do
      load File.expand_path("tasks.rake", __dir__)
    end
  end
end
