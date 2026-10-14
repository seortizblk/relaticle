# Running Relaticle with Docker

Two self-contained stacks live in this directory:

| | File | What it is |
|---|---|---|
| Development | `docker/compose.dev.yml` | php-fpm + nginx, Vite with HMR, Horizon, the scheduler, Reverb, PostgreSQL, Redis, Mailpit. The repository is bind-mounted, so edits are live. |
| Production | `docker/compose.prod.yml` | The repository's own `Dockerfile` (target `production`), plus Horizon, the scheduler and Reverb, PostgreSQL 17 and Redis 7. |

Both are additive: the repository's own `compose.yml`, `compose.dev.yml` (Laravel
Sail) and the published `ghcr.io/relaticle/relaticle` image are untouched.

## Why these exist

The repository already ships two ways to run it. Neither one covers everything:

- `compose.yml` runs the **published image** and has no `reverb` service, while
  the application's default broadcaster is Reverb (`BROADCAST_CONNECTION`).
  Realtime chat streaming therefore does not work in that stack, and the image's
  JavaScript bundle was built without a Reverb key at all.
- `compose.dev.yml` is **Laravel Sail**: it builds from `vendor/laravel/sail`,
  so `composer install` has to run first, and it needs the `sail` wrapper. It
  also starts Meilisearch and Selenium, neither of which this application uses
  today (there is no `laravel/scout` dependency).

What these two files add:

- A development image that needs no local PHP, Node or Composer at all, with
  xdebug, Pint, the test suite and the Pest browser suite ready.
- Reverb wired correctly in both stacks — server side (`BROADCAST_REVERB_*`,
  container-to-container) and browser side (`REVERB_HOST`/`PORT`/`SCHEME`).
- A production stack that builds the application from source instead of
  depending on the published image, and fails at startup — with a message in
  `docker compose logs` — when a secret is missing instead of on the first
  request.

## Requirements

- Docker Engine 24+ with Compose v2 (`docker compose version`).
- ~10 GB of free disk for the images, `vendor/`, `node_modules/` and the
  database volumes.
- PostgreSQL 17 and Redis 7 are provided; nothing has to be installed on the host.

## Development

```bash
cp docker/.env.dev.example docker/.env.dev
docker compose -f docker/compose.dev.yml --env-file docker/.env.dev up -d --build
```

The first start takes a few minutes: the image compiles the PHP extensions
(`intl exif gd imagick bcmath xdebug`), then the entrypoint runs
`composer install` and `pnpm install` into named volumes, generates `APP_KEY`
into the repository's `.env`, and finally the image's Laravel automation runs the
migrations.

| Service | URL |
|---|---|
| Application | http://localhost:8000 |
| Vite (HMR) | http://localhost:5173 |
| Reverb (WebSockets) | ws://localhost:8080 |
| Mailpit | http://localhost:8025 |
| Horizon | http://localhost:8000/horizon |

Or use the shortcuts:

```bash
make -f docker/Makefile help             # every target
make -f docker/Makefile dev-up
make -f docker/Makefile dev-shell
make -f docker/Makefile dev-artisan ARGS="about"
make -f docker/Makefile dev-test
make -f docker/Makefile dev-seed         # local personas (LocalSeeder)
```

Notes:

- On Linux, set `WWWUSER`/`WWWGROUP` in `docker/.env.dev` to `id -u` / `id -g`
  **before the first build**. `www-data` inside the image is then remapped to
  that uid, so the `.env` the entrypoint creates and everything the application
  writes into `storage/` stay editable outside the container. Docker Desktop on
  macOS virtualises ownership and ignores it.
- `.env` in the repository root is created once from `.env.example` and then
  rewritten by `docker/dev/entrypoint.d/40-relaticle-dev-bootstrap.sh` so the
  database, Redis, mail and Reverb hosts point at the containers. Docker env
  vars win over `.env` at runtime, so both paths agree.
- Rebuild (`--build`) only after touching `composer.json`, `package.json`, the
  Dockerfiles or this directory. PHP, Blade, JS and CSS edits are live.
- xdebug is in `develop,debug` mode, trigger-based. `PHP_XDEBUG_MODE=off` in
  `docker/.env.dev` disables it; the debugger listens on host port 9003 at
  `host.docker.internal`.
- The Pest browser suite needs its browser once per volume:
  `make -f docker/Makefile dev-playwright`.
- The development database is PostgreSQL 17 on purpose — the same major as the
  production stack.
- The Makefile runs shell/artisan/test commands as `www-data`, not as root, so
  that files written through them keep the host's ownership. A bare
  `docker compose exec app …` runs as root; pass `-u www-data` if you care.

## Production

```bash
cp docker/.env.prod.example docker/.env.prod
# Fill in APP_KEY, DB_PASSWORD, REDIS_PASSWORD, REVERB_APP_KEY, REVERB_APP_SECRET,
# APP_URL, TRUSTED_HOSTS and HORIZON_ADMIN_EMAILS. The file documents each one.
docker compose -f docker/compose.prod.yml --env-file docker/.env.prod up -d --build
```

`docker/.env.prod` is the only file to edit. It is both the file Compose
interpolates and the `env_file` of every application container; the
infrastructure wiring (`DB_HOST`, `REDIS_HOST`, `BROADCAST_REVERB_HOST`, …) is
set by the compose file and must not be duplicated there.

Only two ports are published: `${APP_PORT:-80}` for the application and
`${REVERB_PUBLISH_PORT:-8080}` for WebSockets. PostgreSQL and Redis stay on the
compose network. Use `docker compose exec postgres pg_dump …` for backups
instead of publishing the database.

### TLS

Neither php-fpm nor Reverb terminates TLS. Terminate it in a reverse proxy
(Caddy, Traefik, nginx) in front of the stack:

- `crm.example.com` → `app:8080` (HTTP).
- `crm.example.com/reverb` or a subdomain → `reverb:8080` (WebSocket upgrade).

Then set `APP_URL=https://crm.example.com`, `SESSION_SECURE_COOKIE=true`,
`REVERB_SCHEME=https`, `REVERB_PORT=443`, `TRUSTED_PROXIES` to the proxy address,
and **rebuild the image**: `VITE_REVERB_*` is compiled into the JavaScript bundle
at build time, so a `restart` is not enough when the public Reverb address
changes.

### Upgrades

```bash
git pull
docker compose -f docker/compose.prod.yml --env-file docker/.env.prod up -d --build
```

The `app` container runs the migrations on start (`AUTORUN_LARAVEL_MIGRATION`,
isolated so that several replicas cannot race). The worker containers never run
them.

### Using the published image instead

Set `IMAGE=ghcr.io/relaticle/relaticle:latest` in `docker/.env.prod`, then
`docker compose ... pull && up -d`. Keep in mind that the project's image is
built in its own CI: its JavaScript bundle carries whatever `VITE_REVERB_*`
values that build had, and no Reverb service is started by these files unless you
keep the `reverb` service from `compose.prod.yml`, which uses the same image.

## Files

```
docker/
├── compose.dev.yml           development stack
├── compose.prod.yml          production stack
├── .env.dev.example          → docker/.env.dev  (git-ignored)
├── .env.prod.example         → docker/.env.prod (git-ignored)
├── Makefile                  shortcuts for both stacks
├── dev/
│   ├── Dockerfile            development image (PHP 8.5, Node 26, pnpm, xdebug)
│   ├── php/                  dev php.ini and xdebug.ini
│   ├── entrypoint.d/         first-start bootstrap (vendor, node_modules, APP_KEY)
│   └── vite.docker.config.js Vite dev server bound to the published ports
└── prod/
    └── entrypoint.d/         startup guard: missing secrets fail loudly
```

## What is deliberately not here

- **Meilisearch / Selenium**: the application has no `laravel/scout` dependency
  and the Pest browser suite drives Playwright, not Selenium. Add them if a
  future feature needs them.
- **A reverse proxy**: installations differ (Caddy, Traefik, nginx, a cloud load
  balancer). The ports to point one at are listed under TLS.
- **A mail relay**: set the `MAIL_*` values in `docker/.env.prod`.
- **Object storage**: set `FILESYSTEM_DISK`/`MEDIA_DISK` and the `AWS_*` keys
  from the repository's `.env.example` if uploads should not live in the
  `storage` volume.
