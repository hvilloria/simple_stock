# Docker Development Environment — Design

**Date:** 2026-08-04
**Status:** Approved, pending implementation

## Goal

Run the full development environment through Docker Compose so no language
runtime, database, or browser has to be installed on the host machine. A fresh
clone should reach a working app with `docker compose build`, `docker compose
up`, and a database bootstrap command.

## Scope

**In scope:** local development and the full test suite, including the four
system specs that require a real browser.

**Out of scope:** production images and deployment. Heroku keeps building the
app with buildpacks from `Procfile`; nothing in this change touches the deploy
path.

**Non-goals:** command shortcuts (Makefile, wrapper scripts in `bin/`).
Commands are typed explicitly as `docker compose exec web <command>`.

## Constraints discovered

- `Gemfile.lock` pins `tailwindcss-ruby 4.1.16-x86_64-linux-gnu`. The `-gnu`
  suffix means glibc, so the app image cannot be Alpine-based (musl).
- The `pg` gem is a native extension and needs `libpq-dev` plus a compiler at
  build time.
- The host runs Linux with UID/GID 1000. Bind mounts do not remap ownership on
  Linux, so the container must run as a user with a matching UID or generated
  files land in the working copy owned by root.
- Host port 65432 is taken by another project's Postgres. Ports published by
  this project must not collide.
- Four system specs under `spec/system/web/` call
  `driven_by :selenium_chrome_headless`, which expects a locally installed
  Chrome.
- `config/database.yml` already reads `POSTGRES_HOST`, `POSTGRES_USER`,
  `POSTGRES_PASSWORD` and `POSTGRES_DB` from the environment, so no change is
  needed there.

## Architecture

Four services on the Compose-managed private network. Services reach each other
by service name; only explicitly published ports are reachable from the host.

| Service | Image | Role | Host port |
| --- | --- | --- | --- |
| `web` | built from `docker/Dockerfile` | Puma, the Rails app | 3005 |
| `css` | same image as `web` | `rails tailwindcss:watch` | — |
| `db` | `postgres:16-alpine` | PostgreSQL | 55432 |
| `selenium` | `selenium/standalone-chromium` | Chrome for system specs | 7900 (noVNC) |

Internal wiring: the app connects to `db:5432` and to `selenium:4444`; during
system specs, Selenium reaches the Capybara test server back at `web:3006`.

### Why `css` is a separate service

Docker's process model is built around a single main process per container: it
owns the logs, receives stop signals, and its death is the container's death.
Running Puma and the Tailwind watcher under Foreman inside one container hides
both processes behind the supervisor, so a silently dead watcher still looks
healthy to Docker.

Split into two services sharing one image and one bind mount, each process gets
its own logs, restart policy, and failure visibility. The two communicate
through the filesystem exactly as they do today: the watcher writes
`app/assets/builds/tailwind.css` and Puma serves it.

Both services declare the same `build:` block and the same `image:` name, so
Compose builds once and starts two containers that differ only in `command:`.

### Why not Alpine for the app image

`ruby:3.3.5-slim` is Debian-based (glibc). Alpine would break the precompiled
Tailwind binary pinned in `Gemfile.lock`. The database image stays on Alpine
because nothing is compiled against it.

## The app image

`docker/Dockerfile`, development-oriented:

- Base `ruby:3.3.5-slim`, matching `.ruby-version`.
- System packages: `build-essential` and `libpq-dev` (to build `pg`),
  `postgresql-client` (`psql`/`pg_dump` inside the container), `git` (bundler).
  The apt cache is removed in the same `RUN` layer that creates it.
- An `app` user created from `UID`/`GID` build args (defaulting to 1000) so
  files generated inside the container are owned by the host user.
- `BUNDLE_PATH=/gems`, outside `/app`, so the code bind mount cannot shadow the
  installed gems.
- `Gemfile` and `Gemfile.lock` are copied on their own and `bundle install` runs
  before anything else, keeping that expensive layer cached across code edits.
- The application code is **not** copied into the image. In development it
  arrives through the bind mount; copying it would only create a shadowed
  duplicate.
- An entrypoint script that removes a stale `tmp/pids/server.pid`, runs
  `bundle check || bundle install` (so a new gem needs a service restart rather
  than an image rebuild), and `exec`s the given command so it becomes PID 1.

A `.dockerignore` keeps `.git`, `log`, `tmp`, `coverage`, `storage`,
`node_modules` and `.env` out of the build context.

## Compose configuration

Notable settings beyond the service table:

- `stdin_open` and `tty` on `web`, required for `binding.irb` and the debugger.
- A `pg_isready` healthcheck on `db` plus `condition: service_healthy` on
  `web`'s `depends_on`. Plain `depends_on` only waits for the container to
  start, not for Postgres to accept connections, which is the usual cause of
  "connection refused" on a first `up`.
- `shm_size: 2gb` on `selenium`. Chrome crashes with the 64 MB Docker default.
- Named volumes: `postgres_data` for the database, `gems` for the bundle. Both
  survive `docker compose down`; `down -v` destroys them.

Environment: `.env` remains the single source of truth for database
credentials. It is read by the Rails app and used to provision the Postgres
container, guaranteeing both sides agree.

## Changes to existing files

### `.env`

Set `POSTGRES_HOST=db` and add `UID=1000` / `GID=1000`. Compose reads these for
the build args because neither shell exports `UID` by default. Credentials and
database name are unchanged.

### `spec/rails_helper.rb`

Bridge Capybara to the remote browser without touching the four spec files.
Capybara allows re-registering an existing driver name, so
`:selenium_chrome_headless` is redefined to drive the remote Selenium node —
but only when `SELENIUM_REMOTE_URL` is set:

- `Capybara.server_host = "0.0.0.0"` so the test server is reachable from
  another container, not just loopback.
- A fixed `Capybara.server_port` so `Capybara.app_host` is predictable.
- `Capybara.app_host` built from `CAPYBARA_APP_HOST` (`http://web`) and that
  port.
- The driver registered with `browser: :remote` and `url:` pointing at
  `SELENIUM_REMOTE_URL`, headless, with `--no-sandbox`.

Outside Docker the variable is absent, the block does not run, and behaviour is
identical to today.

The exact remote-driver registration API shifted across Selenium 4 releases;
the implementation verifies it by running the specs rather than trusting the
snippet.

### `README.md`

A short "Development with Docker" section: first-run bootstrap, daily commands,
and the published URLs.

## Explicitly unchanged

`bin/dev`, `Procfile`, `Procfile.dev`, `config/database.yml`, and the Heroku
deploy. Running the app without Docker keeps working; this change is additive.

## Daily workflow

```bash
# first run
docker compose build
docker compose up -d
docker compose exec web bin/rails db:prepare
docker compose exec web bin/rails db:seed

# day to day
docker compose up
docker compose exec web bin/rails c
docker compose exec web bundle exec rspec
docker compose exec web bundle exec rubocop
docker compose exec db psql -U $POSTGRES_USER simple_stock_development
docker compose down
```

App at `localhost:3005`, database at `localhost:55432`, live view of system
specs at `localhost:7900` (noVNC password `secret`).

## Verification

The design is confirmed only by running, not by inspection:

1. `docker compose up` starts all four services with no restart loops.
2. The app answers at `localhost:3005` and renders styled pages, proving the
   Tailwind watcher's output reaches Puma.
3. Editing a HAML file is picked up without a rebuild; editing a class name
   triggers a CSS recompile.
4. A file generated inside the container (`bin/rails generate migration`) is
   owned by the host user.
5. `bundle exec rspec` passes in full, system specs included.
6. `localhost:7900` shows the browser while system specs run.
7. `docker compose down` followed by `up` preserves database contents.

## Findings from the first run

- `tailwindcss:watch` does not load the Rails environment and never touches the
  database, so `css` only depends on `web`.
- Tailwind's watcher exits with status 0 as soon as stdin reaches EOF, which is
  what a container without a TTY provides. `css` needs `stdin_open` and `tty`.
- `bin/rails server` overrides the port from `config/puma.rb` with its own
  default of 3000, so the command states `-p 3005` explicitly.
- `pg_isready` without `-d` assumes a database named after the user and logs a
  FATAL on every probe, so the healthcheck passes `-d ${POSTGRES_DB}`.
- `RAILS_ENV` must not be set in the image. `spec/rails_helper.rb` assigns the
  test environment with `||=`, so a preset value would silently run the suite
  against the development database.
- The Postgres user no longer needs to match the host account, since peer
  authentication is not involved. It is `simple_stock`, matching the production
  username already in `config/database.yml`.
