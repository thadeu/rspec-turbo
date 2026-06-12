# CLAUDE.md

Guidance for agents working in this repo.

## What this is

`rspec-turbo` is a Ruby gem: a parallel RSpec runner. It spreads a suite across
N worker processes (like `parallel_tests`) but balances by **actual example
count** from a single `rspec --dry-run`, using an LPT (longest-processing-time)
bin-packing heuristic, and splits oversized files across workers by example ID.
Ships a live TTY dashboard, a CI progress mode, schema-fingerprinted test-DB
setup caching, JUnit output, coverage merging, and a slowest folders/files
report.

RSpec-only by design — no Minitest/Cucumber generality. See `README.md` for the
full user-facing docs.

## Pipeline

```
parse argv → DbSetup → FileDiscovery → BatchPlanner → Executor (pool) → Report
```

1. **DbSetup** — one `rails db:drop db:create db:schema:load db:seed` per worker
   slot, each with its own `TEST_ENV_NUMBER`. Cached by a fingerprint of
   `db/schema.rb` + `db/seeds.rb` + worker count.
2. **FileDiscovery** — globs `*_spec.rb`, applies `--exclude-pattern`.
3. **BatchPlanner** — one `rspec --dry-run --format json` counts examples per
   file, then LPT bin-packs into balanced batches; files heavier than a batch's
   fair share are split into example-ID slices.
4. **Executor** — fixed slot pool, recycled until the queue drains. TTY
   dashboard vs. periodic `[progress]` lines on CI.
5. **Report** — failures, slowest folders/files, one-line summary (wall time,
   summed CPU time, speedup).

## File map (`lib/rspec_turbo/`)

| File | Role |
|---|---|
| `config.rb` | env-driven settings + derived log paths — **the single source for all `RSPEC_TURBO_*` / `CI` / `COVERAGE` / `JUNIT_DIR` reads** |
| `terminal.rb` | colour, duration formatting, spinner, separators |
| `options.rb` | split ARGV into rspec flags vs folders |
| `db_setup.rb` | cached parallel test-DB creation (Rails) |
| `file_discovery.rb` | find + filter `*_spec.rb` |
| `batch_planner.rb` | dry-run counting + LPT bin-packing |
| `display.rb` | live spinner + final report + log parsing |
| `worker.rb` | spawn one rspec process per batch |
| `executor.rb` | slot pool + TTY/CI run loops |
| `runner.rb` | top-level orchestration |
| `progress_reporter.rb` | formatter injected into workers (progress bar) |
| `slow_profile.rb` | profiler injected into workers (slow report) |
| `railtie.rb` | registers `spec:turbo` in Rails apps |
| `tasks.rake` | the `spec:turbo` / `coverage:merge` tasks |

Entry point: `exe/rspec-turbo`. Both `lib/rspec_turbo.rb` and the dash-named
shim `lib/rspec-turbo.rb` exist (Bundler `gem "rspec-turbo"` resolves the dash
form).

## Conventions

- **Every file starts with `# frozen_string_literal: true`.**
- **Style is Standard Ruby**, not vanilla RuboCop. The canonical linter is
  `standardrb`; `.rubocop.yml` only re-exports Standard's ruleset for editors.
  Don't add bespoke RuboCop rules.
- **All environment-variable reads live in `Config`.** When adding a knob,
  thread it through `config.rb` and document it in the README's env-var table —
  don't scatter `ENV[...]` across modules.
- `slow_profile.rb` and `progress_reporter.rb` run *inside* worker processes
  (injected via `--require`), so they must degrade gracefully when ActiveSupport
  / Rails is absent — keep them dependency-light.
- Ruby `>= 3.0`. Runtime dep is only `rspec-core`.

## Dev workflow

```sh
bundle install
bundle exec rake            # specs + Standard — must be green before any PR
bundle exec rspec           # specs only
bundle exec standardrb      # lint
bundle exec standardrb --fix
```

Specs live in `spec/rspec_turbo/`. `.rspec` requires `spec_helper` and uses the
documentation formatter.

## Release

1. Bump `lib/rspec_turbo/version.rb` (`RSpecTurbo::VERSION`).
2. Add a dated section to `CHANGELOG.md` (Keep-a-Changelog style:
   Added / Fixed / Changed).
3. `bundle exec rake` green, then `chore: release vX.Y.Z`.

## Don't

- Don't edit anything in `trash/` or `tmp/` (both Standard-ignored, scratch).
- Don't commit `*.gem` build artifacts, `Gemfile.lock`, or `/coverage` — all
  gitignored.
