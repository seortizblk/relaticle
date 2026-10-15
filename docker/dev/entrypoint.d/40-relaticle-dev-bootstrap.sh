#!/bin/sh
#
# Relaticle — development bootstrap.
#
# Runs inside the `app` service only (DEV_BOOTSTRAP=true). serversideup/php
# executes /etc/entrypoint.d/*.sh as root, in `sort -V` order, before s6 starts
# nginx and php-fpm, and aborts the container when a script exits non-zero.
#
# The "40-" prefix matters: it must run BEFORE the image's own
# 50-laravel-automations.sh, which is what runs `migrate` (AUTORUN_* env in
# docker/compose.dev.yml) once the dependencies exist.
#
# Every step is idempotent, because `docker compose up` re-runs this on each new
# container.

set -eu

APP_DIR="${APP_BASE_DIR:-/var/www/html}"
cd "$APP_DIR"

if [ "${DEV_BOOTSTRAP:-false}" != "true" ]; then
    exit 0
fi

PHP_USER="${PHP_FPM_POOL_USER:-www-data}"

say() {
    echo "🔧 relaticle-dev: $*"
}

# set_env writes a value into .env without touching the rest of the file.
# Docker env vars win over .env at runtime (Laravel's dotenv is immutable), but
# .env is what artisan, `php artisan test` and Vite read when they run by hand.
set_env() {
    key="$1"
    value="$2"
    if grep -qE "^${key}=" .env; then
        sed -i "s|^${key}=.*|${key}=${value}|" .env
    else
        printf '%s=%s\n' "$key" "$value" >> .env
    fi
}

###############################################################################
# 1. .env
###############################################################################
# It lives on the bind mount, so an APP_KEY survives `docker compose down`.
if [ ! -f .env ]; then
    if [ ! -f .env.example ]; then
        echo "❌ relaticle-dev: .env.example not found — is the repository mounted at ${APP_DIR}?" >&2
        exit 1
    fi
    say "creating .env from .env.example"
    cp .env.example .env
fi

say "pointing .env at the compose services"
set_env APP_ENV local
set_env APP_DEBUG true
set_env APP_URL "${APP_URL:-http://localhost:8000}"
set_env APP_TIMEZONE "${APP_TIMEZONE:-UTC}"
set_env LOG_CHANNEL stderr
set_env LOG_LEVEL "${LOG_LEVEL:-debug}"

set_env DB_CONNECTION pgsql
set_env DB_HOST postgres
set_env DB_PORT 5432
set_env DB_DATABASE "${DB_DATABASE:-relaticle}"
set_env DB_USERNAME "${DB_USERNAME:-relaticle}"
set_env DB_PASSWORD "${DB_PASSWORD:-secret}"

set_env REDIS_CLIENT phpredis
set_env REDIS_HOST redis
set_env REDIS_PORT 6379
set_env CACHE_STORE redis
set_env SESSION_DRIVER redis
set_env QUEUE_CONNECTION redis

set_env MAIL_MAILER smtp
set_env MAIL_HOST mailpit
set_env MAIL_PORT 1025

# The browser talks to the published Reverb port; the app containers reach the
# reverb container by its service name.
set_env BROADCAST_CONNECTION reverb
set_env REVERB_APP_ID "${REVERB_APP_ID:-relaticle}"
set_env REVERB_APP_KEY "${REVERB_APP_KEY:-relaticle-local-key}"
set_env REVERB_APP_SECRET "${REVERB_APP_SECRET:-relaticle-local-secret}"
set_env REVERB_HOST "${REVERB_HOST:-localhost}"
set_env REVERB_PORT "${REVERB_PORT:-8080}"
set_env REVERB_SCHEME http
set_env BROADCAST_REVERB_HOST reverb
set_env BROADCAST_REVERB_PORT 8080
set_env BROADCAST_REVERB_SCHEME http
set_env BROADCAST_REVERB_VERIFY false

# The VITE_* values in .env.example are written as "${REVERB_APP_KEY}" and
# friends, so dotenv expands them from the lines above.

###############################################################################
# 2. Writable directories
###############################################################################
# The bind mount carries the host's user ids; the container writes as www-data.
mkdir -p \
    storage/app/public \
    storage/framework/cache/data \
    storage/framework/sessions \
    storage/framework/views \
    storage/logs \
    bootstrap/cache
chown -R "${PHP_USER}:${PHP_USER}" storage bootstrap/cache

###############################################################################
# 3. PHP dependencies
###############################################################################
if [ ! -f vendor/autoload.php ]; then
    say "composer install"
    composer install \
        --no-interaction \
        --prefer-dist \
        --no-scripts \
        --no-progress
fi

if ! grep -qE '^APP_KEY=.+' .env; then
    say "generating APP_KEY"
    php artisan key:generate --force --no-interaction
fi

# The post-autoload-dump scripts (package:discover, filament:upgrade,
# icons:cache) are safe without a database — the production image runs them at
# build time — and they are what registers the packages.
say "composer dump-autoload"
composer dump-autoload --optimize --no-interaction

###############################################################################
# 4. Frontend dependencies
###############################################################################
# --ignore-scripts keeps Playwright from downloading browsers on `up`.
# Install them when you need the browser suite:
#   docker compose exec app pnpm exec playwright install --with-deps chromium
if [ ! -f node_modules/.pnpm/lock.yaml ]; then
    say "pnpm install"
    pnpm install --frozen-lockfile --ignore-scripts
fi

chown -R "${PHP_USER}:${PHP_USER}" storage bootstrap/cache node_modules 2>/dev/null || true
# The developer edits .env on the host; the container must not leave it owned by
# root, or every editor hit an EACCES.
chown "${PHP_USER}:${PHP_USER}" .env 2>/dev/null || true

say "ready; migrations run next (50-laravel-automations.sh)"
