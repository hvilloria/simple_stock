# simple_stock

Inventory, sales and supplier-invoice management for an auto parts business.
Rails 7.2, PostgreSQL, Hotwire, HAML, TailwindCSS.

## Development with Docker

Docker is the recommended way to work on this project: nothing but Docker
itself has to be installed on the host. Running the app directly with
`bin/dev` still works and is unaffected.

### Requirements

Docker Engine and the Compose plugin (`docker compose version`).

### Configuration

Create a `.env` file in the project root (it is git-ignored):

```
POSTGRES_HOST=db
POSTGRES_USER=simple_stock
POSTGRES_PASSWORD=simple_stock
POSTGRES_DB=simple_stock_development

UID=1000
GID=1000
```

`POSTGRES_HOST` must be `db`, the Compose service name. `POSTGRES_PASSWORD`
cannot be empty — the Postgres image refuses to initialize without one. `UID`
and `GID` must match the host user (`id -u`, `id -g`) so files generated inside
the container stay editable from the working copy.

### First run

```bash
docker compose build
docker compose up
docker compose exec web bin/rails db:prepare
```

`db:prepare` creates the database, loads the schema and runs the seeds.

### Services

| URL | What |
| --- | --- |
| http://localhost:3005 | The application |
| localhost:55432 | PostgreSQL, for external clients such as DBeaver |
| http://localhost:7900 | Live view of the browser during system specs (password `secret`) |

Four containers run: `web` (Puma), `css` (the Tailwind watcher), `db` and
`selenium`.

### Everyday commands

```bash
docker compose up                  # start everything
docker compose down                # stop; database and gems are preserved
docker compose logs -f css         # follow one service

docker compose exec web bin/rails c
docker compose exec web bundle exec rspec
docker compose exec web bundle exec rubocop
docker compose exec db psql -U simple_stock simple_stock_development
```

System specs drive a Chrome running in the `selenium` container; no browser is
needed on the host.

### Notes

Adding a gem needs no rebuild — update the `Gemfile` and run
`docker compose restart web css`; the entrypoint installs it into the `gems`
volume. Rebuild the image only when `docker/Dockerfile` changes.

Database credentials are applied only when the database is first initialized.
Changing `POSTGRES_PASSWORD` afterwards has no effect until the volume is
recreated with `docker volume rm simple_stock_postgres_data`.

## Deployment

Heroku, from `Procfile`, using buildpacks. The Docker setup is for local
development only and is not part of the deploy path.

## Documentation

- `AGENTS.md` — operating rules for agents working on this repository
- `docs/DEVELOPMENT_GUIDE.md` — architecture rules and business constraints
- `docs/CODE_PATTERNS.md` — concrete implementation patterns
- `docs/UI_DESIGN_SPEC.md` — frontend conventions
- `docs/TESTING_GUIDE.md` — testing conventions
