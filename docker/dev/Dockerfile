# syntax=docker/dockerfile:1

###########################################
# Relaticle — development image
###########################################
#
# One image for every PHP service in docker/compose.dev.yml (app, vite, horizon,
# scheduler, reverb): the same runtime as production (serversideup/php 8.5
# fpm-nginx, Debian trixie) plus the tooling a developer needs — xdebug,
# Node + pnpm, git, `pnpm run build` and the Pest browser suite (Playwright).
#
# The application code is NOT baked in. docker/compose.dev.yml bind-mounts the
# repository over /var/www/html, so editing a file is enough:
#
#   docker build -f docker/dev/Dockerfile -t relaticle-dev:local .
#
# The base image runs as www-data. This image stays root on purpose: the
# entrypoint has to chown the bind-mounted storage/ and bootstrap/cache, and
# php-fpm drops to www-data per its pool configuration.
#
# See docker/README.md.

ARG PHP_VERSION=8.5
ARG NODE_VERSION=26
# The uid/gid of the developer on the host. www-data is remapped to it so that
# files the application writes — storage/, .env, node_modules/ — stay editable
# outside the container instead of landing as root or as uid 33.
# Set in docker/.env.dev (WWWUSER=$(id -u), WWWGROUP=$(id -g)) before the first
# build. Docker Desktop on macOS virtualises ownership, so it only matters on
# Linux.
ARG WWWUSER=1000
ARG WWWGROUP=1000

###########################################
# Node, copied into the PHP image below
###########################################
# Debian, not Alpine: @tailwindcss/oxide, esbuild and playwright ship
# platform-specific binaries, and node_modules lives in a volume shared between
# the app container (glibc, PHP) and the vite container (glibc, Node). Both have
# to be the same libc — and `node:*-trixie` matches the PHP base image.
FROM node:${NODE_VERSION}-trixie-slim AS node

###########################################
# Development image
###########################################
FROM serversideup/php:${PHP_VERSION}-fpm-nginx

USER root

# Extensions the app needs that the base image does not ship.
# serversideup/php already provides opcache, pcntl, posix, pdo_pgsql, pdo_mysql,
# redis (phpredis, the app's REDIS_CLIENT) and zip. intl and gd/bcmath/exif are
# hard requirements: composer.json, filament/support, spatie/laravel-medialibrary
# and moneyphp/money. xdebug is development only.
RUN install-php-extensions intl exif gd imagick bcmath xdebug

# git: composer resolves a VCS repository (pest, in composer.json).
# postgresql-client: pg_isready, used while waiting for the database.
# procps: pgrep, used by the image's healthcheck-* helpers.
# passwd: usermod/groupmod, for the uid remap below.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git \
        unzip \
        less \
        passwd \
        procps \
        postgresql-client \
        libstdc++6 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Match the host's uid/gid (this image stays root: s6, nginx and php-fpm need it
# to start — php-fpm drops to www-data per its pool configuration, and every
# command in docker/Makefile runs as www-data).
RUN if [ "${WWWUSER}" != "33" ] && [ "${WWWUSER}" != "0" ]; then \
        groupmod -o --gid "${WWWGROUP}" www-data \
        && usermod -o --uid "${WWWUSER}" --gid "${WWWGROUP}" www-data; \
    fi \
    && chown -R www-data:www-data /var/cache/nginx /var/lib/nginx /var/log/nginx /var/www/html

# Node and pnpm. The pnpm version comes from package.json#packageManager, the
# same pin the production image honours (corepack is gone from Node 25+).
COPY --from=node /usr/local/ /usr/local/
COPY package.json /tmp/pnpm-pin/package.json
RUN npm install -g "$(node -p 'require("/tmp/pnpm-pin/package.json").packageManager')" \
    && rm -rf /tmp/pnpm-pin

# Defaults. Everything here can be overridden per service in compose.
ENV SSL_MODE=off \
    AUTORUN_ENABLED=false \
    PHP_OPCACHE_ENABLE=0 \
    PHP_DISPLAY_ERRORS=On \
    PHP_MEMORY_LIMIT=1G \
    PHP_MAX_EXECUTION_TIME=0 \
    COMPOSER_MEMORY_LIMIT=-1 \
    COMPOSER_ALLOW_SUPERUSER=1 \
    PHP_XDEBUG_MODE=develop,debug \
    PHP_XDEBUG_START_WITH_REQUEST=trigger \
    PHP_XDEBUG_CLIENT_HOST=host.docker.internal \
    PHP_XDEBUG_CLIENT_PORT=9003 \
    PHP_XDEBUG_IDEKEY=VSCODE

# The "zz-" prefix wins over the image's own conf.d files.
COPY docker/dev/php/ /usr/local/etc/php/conf.d/

# serversideup/php runs every /etc/entrypoint.d/*.sh, as root, before s6 starts
# the services, and aborts the container when one of them exits non-zero.
COPY docker/dev/entrypoint.d/ /etc/entrypoint.d/
RUN chmod 755 /etc/entrypoint.d/*.sh

WORKDIR /var/www/html
