# AGENTS: Isilon Tracker

## Scope and ethos
- Applies repo-wide unless superseded by nested AGENTS.
- Optimize clarity, minimal diffs, consistency with established patterns.
- Fix root causes; avoid speculative refactors unrelated to the task.
- Keep secrets out of code/logs; sanitize examples and redact tokens.
- Ask before running commands that inspect environment variables.
- Stay within repo; do not read homedir-sensitive files.

## Stack overview
- Ruby 3.4.3 (`.ruby-version`), Rails app on SQLite per `config/database.yml`.
- RSpec with SimpleCov LCOV output at `coverage/lcov/app.lcov`.
- Frontend: esbuild (ESM), Stimulus, Turbo, Bootstrap, Wunderbaum.
- Styles: Sass -> `app/assets/builds`; Bootstrap icons available.
- Admin UI via Administrate dashboards in `app/dashboards`.
- Stimulus controllers under `app/javascript/controllers`; entrypoint `app/javascript/application.js`.
- No Cursor or Copilot rule files present at time of writing.

## Repository orientation
- Server code: `app/models`, `app/controllers`, `app/views`, `app/services`.
- Dashboards: `app/dashboards`; serializers: `app/serializers`.
- Specs live in `spec/**`; support helpers auto-loaded from `spec/support`.
- SQLite DBs in `storage/` (development/test/production splits).

## Environment and secrets
- Authentication uses Google OAuth: set `GOOGLE_OAUTH_CLIENT_ID` and `GOOGLE_OAUTH_SECRET`.
- Use `.env`/direnv for local secrets; never commit credentials or `.env`.
- Avoid logging tokens; prefer Rails logger over `puts`.
- Docker builds need `RAILS_MASTER_KEY` and `SECRET_KEY_BASE` set.

## Dependency install
- Ruby gems: `bundle install`.
- JS packages: `bundle exec yarn install`.
- Node version not pinned; esbuild bundled via devDependency.

## Running the app
- Dev stack with file watchers: `bin/dev` (Rails + JS + CSS).
- Standalone server: `bin/rails server -p 3000` (PORT unset in Procfile).
- Docker: `make build` then `make run` (binds 3001->3000 by default).

## Build commands
- JS bundle: `yarn build` bundles `app/javascript/*.*` to `app/assets/builds`.
- CSS build: `yarn build:css` (calls `yarn build:css:compile` with Sass).
- One-off CSS compile: `yarn build:css:compile`.
- Asset precompile for CI/prod: `bin/rails assets:precompile`.
- Production Docker image: `make build`; respect version tags/registry defaults.

## Linting and formatting
- Ruby lint: `bundle exec rubocop`; use `-A` autocorrect only when safe.
- Dockerfile lint (local): `make lint` (hadolint).
- RuboCop base is rubocop-rails-omakase: 2-space indent, double quotes, no trailing commas.
- Keep `# frozen_string_literal: true` where present; add for new Ruby files unless template omits.
- Avoid large formatting churn; match existing whitespace/semicolon style per file.

## Testing commands
- Full suite: `bundle exec rspec` or `bundle exec rspec spec`.
- Single file: `bundle exec rspec spec/path/to/file_spec.rb`.
- Single example: `bundle exec rspec spec/path/to/file_spec.rb:LINE`.
- Single example by description: `bundle exec rspec spec/path/to/file_spec.rb -e "example name"`.
- System specs use Capybara/Cuprite; precompile assets if packs missing.
- Remove `:focus`/`fdescribe`/`fit`; ensure pending migrations are applied.

## Database and migrations
- SQLite locations: `storage/development.sqlite3`, `storage/test.sqlite3`.
- Fresh setup: `bundle exec rake db:setup` then `bundle exec rake db:migrate`.
- Avoid manual schema edits; use migrations with reversible `change`/`up`/`down`.
- Maintain ordering; avoid destructive data changes without backups.

## Domain rake tasks
- Import Isilon assets: `bundle exec rails sync:assets[scan_output.applications-backup.csv]`.
- If zsh nomatch errors, escape brackets or quote the task (`"sync:assets[...]"`).
- TIFF dedup analysis: `bundle exec rails sync:tiffs[deposit]` or `[media-repository]`.
- Task output logs to `log/isilon-sync.log`; monitor stdout for progress.

## Application behavior
- Navigation data via `NavigationData`; session timeout via `SessionTimeoutData`.
- Authentication required for explorer and admin; seed users with README runner snippet when needed.
- Avoid reading outside repo or user home directories per system rules.

## Ruby style and naming
- Follow rubocop-rails-omakase defaults; snake_case methods/vars, CamelCase classes/modules.
- Prefer guard clauses to reduce nesting; use early returns.
- Prefer explicit scopes/queries; keep SQL within ActiveRecord APIs when possible.
- Use strong params in controllers; permit only necessary keys.
- Prefer service objects for non-trivial workflows (`app/services/sync_service/*`).
- Use `find_or_create_by!` with retry/backoff where races are possible.
- Keep migrations idempotent; avoid irreversible data loss.

## Controllers, serializers, dashboards
- Keep controllers skinny; push heavy logic into POROs/services.
- Include `before_action :authenticate_user!` on protected controllers.
- Serializers should expose minimal, explicit attributes; avoid implicit defaults.
- Administrate dashboards: concise labels, correct associations, and field ordering.
- Avoid inline SQL in controllers; lean on scopes or helper methods.

## Error handling and logging
- Rescue narrowly and close to the source; avoid broad `StandardError`.
- Use Rails logger or `stdout_and_log` pattern for sync services with context.
- Re-raise on persistence-critical failures unless intentionally handled.
- Avoid silent failures; return meaningful messages or errors to callers.
- Include retries with backoff and max attempts for transient operations.

## RSpec style
- Use FactoryBot for data; fixtures only when necessary under `spec/fixtures`.
- Descriptive example strings; prefer `let`/`subject` for shared setup.
- Keep specs deterministic; rely on default randomization without order coupling.
- Use `eq`/`match` expectations; avoid `be_truthy`/`be_falsey` unless checking truthiness.
- System specs: wait for Turbo/Stimulus events instead of sleeps; target elements explicitly.
- Shared helpers live in `spec/support` (auto-required by `rails_helper`).

## JavaScript and Stimulus style
- Use ES module imports; keep globals minimal (Bootstrap/Wunderbaum exposed in `application.js`).
- Prefer `const`/`let`; avoid `var`.
- Match file-local semicolon patterns (controllers mostly none; entrypoints include semicolons).
- Define Stimulus `static targets` and `values` explicitly; clean up listeners in `disconnect`.
- Guard DOM queries before use; bail early if elements missing.
- Use template literals over string concatenation.
- Update UI via `textContent`/`value`; avoid `innerHTML` unless sanitized.
- Debounce/throttle expensive DOM updates when needed.

## CSS and assets
- Sass entrypoint: `app/assets/stylesheets/application.css.scss`; compiled CSS in `app/assets/builds`.
- Prefer Bootstrap utility classes before custom styles.
- Scope component styles to containers; avoid global bleed.
- Avoid inline styles; use classes and data attributes.
- Regenerate builds (`yarn build` / `yarn build:css`) when adjusting assets.

## Accessibility and UX
- Ensure buttons/links have discernible text; rely on Bootstrap alerts for flashes.
- Manage focus in modals; provide close controls (Bootstrap defaults apply).
- Do not rely solely on color; include text labels or icons with text.
- Favor keyboard-friendly interactions in Stimulus controllers.

## Git and branch hygiene
- Default branch: `main`; rebase feature branches when reasonable.
- Keep changes focused; avoid unrelated refactors in same PR.
- Do not commit secrets or `.env`; update `.gitignore` if needed.
- Use imperative, concise commit messages; avoid history rewrites unless requested.

## CI/CD notes
- `.github/workflows/lint-test.yml` runs RuboCop, asset precompile, then RSpec.
- Coverage uploads to Coveralls; keep LCOV path stable at `coverage/lcov/app.lcov`.
- Run lint/tests locally before pushing to keep pipelines green.
- Docker image publishing driven by Makefile targets; respect tags/registry defaults.

## Cursor and Copilot rules
- No `.cursor/rules`, `.cursorrules`, or `.github/copilot-instructions.md` present currently.
- If added later, obey the most specific applicable file for touched paths.

## Quick command recap
- Dev server: `bin/dev`.
- Lint: `bundle exec rubocop`.
- Test all: `bundle exec rspec`.
- Test one file: `bundle exec rspec spec/path/to/file_spec.rb`.
- Test one example: `bundle exec rspec spec/path/to/file_spec.rb:LINE` or `... -e "example name"`.
- Build assets: `yarn build`, `yarn build:css`.
- Import data: `bundle exec rails sync:assets[scan_output.applications-backup.csv]`.
- TIFF analysis: `bundle exec rails sync:tiffs[deposit]`.

## Closing
- Mirror nearby style when unsure; keep diffs small.
- Document new tasks or workflows here and in README when added.
- Ask for clarification before running environment-inspecting commands.
- Avoid adding code comments unless explicitly requested.
