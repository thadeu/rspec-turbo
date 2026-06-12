# Changelog

## [0.1.1] - 2026-06-12

### Added
- Three entry points: the `rspec-turbo` binary plus a `spec:turbo` Rake task
  (reachable as both `rake spec:turbo` and `rails spec:turbo`), registered in
  Rails apps through a Railtie.
- `coverage:merge` Rake task that collates per-worker SimpleCov result files
  with `SimpleCov.collate`, emitting JSON on CI (`JSONFormatter`) and HTML
  locally (`HTMLFormatter`); glob overridable via `RSPEC_TURBO_COVERAGE_GLOB`.

### Fixed
- Workers and the dry-run now force `RAILS_ENV=test`, so they always target the
  `*_test` databases `DbSetup` created — instead of relying on the project's
  `rails_helper` to set it (which broke when launched via `rake`/`rails`, where
  the parent process boots in development).

## [0.1.0] - 2026-06-12

Initial extraction from the single-file `turbo.rb` runner into a gem.

### Added
- Parallel RSpec runner with dry-run-based example counting and LPT bin-packing.
- Splitting of oversized spec files across workers by example ID.
- Schema-fingerprinted test DB setup caching (Rails).
- Live TTY dashboard and CI-friendly periodic progress mode.
- Slowest folders/files report fed by the bundled `slow_profile` profiler,
  enabled by default (disable with `RSPEC_TURBO_NO_PROFILE=1`) and safe outside
  Rails (times examples without counting SQL when ActiveSupport is absent).
- JUnit XML output (`JUNIT_DIR`) and SimpleCov coverage merging (`COVERAGE=1`).

### Fixed (versus the original script)
- `DbSetup#show_log` referenced an undefined `w` variable on failure.
- Missing `require "set"` for `FileDiscovery`.
- A dead `Process.clock_gettime` call in `DbSetup#run!`.
- `"\nTop \d"` string literal that was meant to be a regular expression.
