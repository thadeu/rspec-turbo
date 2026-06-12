# ⚡ rspec-turbo

[![Gem Version](https://img.shields.io/gem/v/rspec-turbo)](https://rubygems.org/gems/rspec-turbo)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.0-CC342D)](https://www.ruby-lang.org)
[![Style](https://img.shields.io/badge/code_style-standard-brightgreen)](https://github.com/standardrb/standard)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE.txt)

**Run your whole RSpec suite in parallel — with zero config.**

`rspec-turbo` spreads your specs across every core, balancing the load by the
**actual number of examples** (not file size, not a stale timing log) and even
splitting a single oversized file across workers. One command, a live progress
dashboard, and a report that tells you exactly which folders are slowing you
down.

```sh
bundle add rspec-turbo --group test
bundle exec rspec-turbo
```

That's it. No runtime logs to maintain, no grouping flags to tune.

---

## 🏎️ See it run

```text
====================================================================
  RSpec Turbo - Parallel
====================================================================

  ✓ 8 DB(s) ready (0s)
  ✓ 4210 examples · 312 files · 8 batches (~526 each) (3s)

  ✓ worker/01  1m02s  PASS   requests/v1
  ✓ worker/02  58s    PASS   models · services
  ⠹ worker/03  ~520 ex  46s   jobs · mailers
  ...

  ▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░  2731/4210  65%

====================================================================
  RSpec Turbo Report
====================================================================

  Slowest folders  ↳ optimize these first

  requests/v1                                     1m12s  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
  models                                            48s  ▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░
  services                                          31s  ▓▓▓▓▓▓▓▓░░░░░░░░░░░░░

  ✓ All passed  ·  4210 examples  ·  8 workers  ·  wall 1m04s  sum 7m58s  7.4x
```

*(Illustrative output — your speedup scales with your cores.)*

---

## Why not just use `parallel_tests`?

[`parallel_tests`](https://github.com/grosser/parallel_tests) is a great,
battle-tested tool — and if you run Minitest, Cucumber, Test::Unit **and**
RSpec, its multi-framework reach is exactly what you want.

But if your project is **RSpec-only**, that generality costs you. `rspec-turbo`
does one thing and tunes hard for it:

| | `parallel_tests` | **`rspec-turbo`** |
|---|---|---|
| **Scope** | Multi-framework (RSpec, Minitest, Cucumber…) | RSpec only — focused and lean |
| **Default balancing** | By file **size** (bytes) — a rough proxy for time | By **actual example count** from one `rspec --dry-run` |
| **Best-case balancing** | `--group-by runtime`, needs a runtime log you record and keep fresh | Recomputed every run from the dry-run — **always current, nothing to maintain** |
| **Unit of work** | A whole file — one giant `*_spec.rb` stalls a process | A file **or** example-ID slices — **splits big files across workers** |
| **Config to balance well** | Generate + commit `tmp/parallel_runtime_rspec.log` | **None** — good distribution out of the box |
| **Live output** | Per-process stdout, interleaved | Live TTY dashboard (spinner per worker + global bar) / clean CI progress |
| **Final report** | Concatenated process outputs | **One consolidated report**: failures per worker, speedup, slowest folders/files |
| **Slow-test insight** | DIY (`--profile` per process, aggregate yourself) | **Built in, on by default** — per-file time + SQL query counts, aggregated |
| **Test-DB setup** | `rake parallel:prepare` (you decide when to re-run) | Automatic, **schema-fingerprint cached** — skipped when the schema hasn't changed |
| **JUnit / coverage merge** | Extra wiring | Built in (`JUNIT_DIR`, `COVERAGE=1`) |

### What that means in practice

- **Better balance, no homework.** `parallel_tests`' file-size grouping puts a
  500-line file with 3 slow examples in the same weight class as a 500-line file
  with 80 fast ones. `rspec-turbo` counts the *examples* (via a fast dry-run) and
  packs them with a longest-processing-time-first heuristic — and it does this
  every run, so it never goes stale and there's no runtime log to commit.
- **No single-file bottleneck.** When one mega `*_spec.rb` holds 20% of your
  suite, a file-based splitter leaves one process grinding while the rest idle.
  `rspec-turbo` slices that file by example ID across workers.
- **Answers, not just speed.** Every run ends with a ranked "slowest folders /
  files" report (and SQL query counts under Rails), so you know *what* to
  optimize next — not just that the suite is slow.

---

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
└── slow_profile.rb      # profiler injected into workers (slow report)
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

## Contributing

Issues and pull requests are welcome. Run `bundle exec rake` before opening a
PR — it must be green (specs + Standard).

**If `rspec-turbo` shaves minutes off your CI, drop a ⭐ on the repo** — it helps
other RSpec teams find it.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
