# frozen_string_literal: true

require_relative "lib/rspec_turbo/version"

Gem::Specification.new do |spec|
  spec.name = "rspec-turbo"
  spec.version = RSpecTurbo::VERSION
  spec.authors = ["thadeu"]
  spec.email = ["tadeuu@gmail.com"]

  spec.summary = "Parallel RSpec runner with smart, dry-run-based example balancing."
  spec.description = <<~DESC
    rspec-turbo runs your RSpec suite across N processes like parallel_tests,
    but balances work by actual example count (from a single --dry-run) using an
    LPT bin-packing heuristic, splitting oversized files across workers. It ships
    a live TTY dashboard, a CI-friendly progress mode, schema-fingerprinted test
    DB setup caching, JUnit output, coverage merging, and a slowest folders/files
    report.
  DESC
  spec.homepage = "https://github.com/thadeu/rspec-turbo"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.{rb,rake}", "exe/*", "README.md", "LICENSE.txt", "CHANGELOG.md"]
  spec.bindir = "exe"
  spec.executables = ["rspec-turbo"]
  spec.require_paths = ["lib"]

  spec.add_dependency "rspec-core", ">= 3.0"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "standard", "~> 1.50"
end
