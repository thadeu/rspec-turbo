# rspec-turbo

Parallel RSpec runner — like `parallel_tests`, but it balances work by the
**actual number of examples** (counted in a single `--dry-run`) instead of by
file or static timings, and it can split a single oversized spec file across
workers. Ships a live terminal dashboard, a CI-friendly progress mode,
schema-fingerprinted test-DB setup caching, JUnit output, coverage merging, and
a slowest-folders/files report.

## Install

Add it to the `:test` group of your Gemfile:

```ruby
group :test do
  gem "rspec-turbo"
end
```

```sh
bundle install
```

## Usage

```sh
bundle exec rspec-turbo                              # all of spec/
bundle exec rspec-turbo spec/models lib              # specific folders
bundle exec rspec-turbo spec/models/project_spec.rb  # a single file
bundle exec rspec-turbo --exclude-pattern "spec/requests/**/*"
bundle exec rspec-turbo --fail-fast spec/models

RSPEC_TURBO_MAX=6 bundle exec rspec-turbo            # cap workers
RSPEC_TURBO_FORCE_SETUP=1 bundle exec rspec-turbo    # recreate test DBs
```

Any RSpec flag you pass through (`--tag`, `--seed`, `--order`, …) is forwarded
to every worker.

## How it works

```
parse argv → DbSetup → FileDiscovery → BatchPlanner → Executor (pool) → Report
```

1. **DbSetup** — spawns one `rails db:drop db:create db:schema:load db:seed` per
   worker slot (each with its own `TEST_ENV_NUMBER`). Cached by a fingerprint of
   `db/schema.rb` + `db/seeds.rb` and the worker count, so repeat runs skip it.
2. **FileDiscovery** — globs `*_spec.rb`, applies `--exclude-pattern`.
3. **BatchPlanner** — one `rspec --dry-run --format json` counts examples per
   file, then bin-packs files into balanced batches (Longest-Processing-Time
   first). Files heavier than a batch's fair share are split into example-ID
   slices so no single file bottlenecks a worker.
4. **Executor** — a fixed pool of slots; each finished slot is recycled until
   the queue drains. Live dashboard on a TTY, periodic `[progress]` lines on CI.
5. **Report** — failures, slowest folders/files, and a one-line summary with
   wall time, summed CPU time and the resulting speedup.

## Requirements

- **Rails** — `DbSetup` uses `rails db:*`. (Non-Rails projects can still run if
  the databases already exist; set `RSPEC_TURBO_FORCE_SETUP=0`, the default, and
  the setup is skipped on a cache hit.)
- **`rspec_junit_formatter`** — only when `JUNIT_DIR` is set.
- **A `coverage:merge` rake task** — only when `COVERAGE=1`. rspec-turbo runs
  each worker with its own `TEST_ENV_NUMBER`, then calls
  `rake coverage:merge` to combine the per-worker SimpleCov results.

## Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `RSPEC_TURBO_MAX` | nproc | Number of parallel workers |
| `RSPEC_TURBO_LOG_DIR` | `tmp/rspec-turbo` | Where per-worker logs live |
| `RSPEC_TURBO_FORCE_SETUP` | off | `1` recreates the test DBs even if cached |
| `RSPEC_TURBO_PROGRESS_INTERVAL` | `30` | Seconds between CI progress lines |
| `COVERAGE` | `0` | `1` merges SimpleCov results after the run |
| `JUNIT_DIR` | — | Emit one JUnit XML per worker into this dir |
| `CI` | — | Forces the plain (non-TTY) progress mode |

### Slowest-files report (on by default)

The "Slowest folders / Slowest files" section is fed by the bundled
`slow_profile` hook, loaded into every worker. It is **on by default**: each
worker times every example, and under Rails it also counts SQL queries via
`ActiveSupport::Notifications`. Outside Rails it degrades gracefully — it just
times examples and reports zero queries.

Turn it off with the master kill switch:

```sh
RSPEC_TURBO_NO_PROFILE=1 bundle exec rspec-turbo
```

| Variable | Default | Purpose |
|---|---|---|
| `RSPEC_TURBO_NO_PROFILE` | off | `1` disables profiling entirely (master kill switch) |
| `RSPEC_PROFILE_THRESHOLD_TIME` | `0.2` | Seconds an example must exceed to make the "slow examples" list |
| `RSPEC_PROFILE_THRESHOLD_QUERIES` | `30` | Query count an example must exceed to make that list |
| `RSPEC_PROFILE_GROUP_BY` | — | `1`/`auto`, a base path, or a comma list of folders to bucket by |

## Architecture

```
lib/rspec_turbo/
├── config.rb            # env-driven settings + derived log paths
├── terminal.rb          # colour, duration formatting, spinner, separators
├── options.rb           # split ARGV into rspec flags vs folders
├── db_setup.rb          # cached parallel test-DB creation (Rails)
├── file_discovery.rb    # find + filter *_spec.rb files
├── batch_planner.rb     # dry-run counting + LPT bin-packing
├── display.rb           # live spinner + final report + log parsing
├── worker.rb            # spawn one rspec process per batch
├── executor.rb          # the slot pool + TTY/CI run loops
├── runner.rb            # top-level orchestration
├── progress_reporter.rb # formatter injected into workers (progress bar)
└── slow_profile.rb      # opt-in profiler injected into workers (slow report)
```

## Development

```sh
bundle install
bundle exec rake          # runs the specs + Standard
bundle exec rspec         # specs only
bundle exec standardrb    # lint
bundle exec standardrb --fix
```

Style is enforced by [Standard Ruby](https://github.com/standardrb/standard).
The `.rubocop.yml` simply loads Standard's ruleset so editors and tooling that
speak RuboCop pick up the same rules; the canonical runner is `standardrb`.
VS Code is pre-wired (`.vscode/settings.json`) to format on save with Standard
via the Ruby LSP extension.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
