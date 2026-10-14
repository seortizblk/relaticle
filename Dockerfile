# syntax=docker/dockerfile:1

###########################################
# Stage 1: Composer dependencies
###########################################
FROM composer:2 AS composer

WORKDIR /app

COPY composer.json composer.lock ./
RUN composer install \
    --no-dev \
    --no-interaction \
    --no-scripts \
    --no-autoloader \
    --prefer-dist \
    --ignore-platform-reqs

###########################################
# Stage 2: Build frontend assets
###########################################
FROM node:26-alpine AS frontend

WORKDIR /app

# Corepack is gone from Node 25+, and letting pnpm fetch its own pinned version
# needs glibc, so install the exact version package.json already pins.
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN npm install -g "$(node -p 'require("./package.json").packageManager')" \
    && pnpm install --frozen-lockfile --ignore-scripts

# Copy source files needed for build
COPY vite.config.js ./
COPY resources ./resources
COPY public ./public
COPY packages ./packages

# Copy vendor for Filament theme CSS
COPY --from=composer /app/vendor ./vendor

# resources/js/echo.js reads these through import.meta.env, which Vite resolves
# at BUILD time — the browser bundle carries whatever was set here. A
# self-hosted deployment has to pass its public Reverb address as build args
# (docker/compose.prod.yml does), or the Echo client ships with an undefined key
# and every page throws "You must pass your app key".
ARG VITE_APP_NAME=Relaticle
ARG VITE_REVERB_APP_KEY=
ARG VITE_REVERB_HOST=localhost
ARG VITE_REVERB_PORT=8080
ARG VITE_REVERB_SCHEME=http

ENV VITE_APP_NAME=${VITE_APP_NAME} \
    VITE_REVERB_APP_KEY=${VITE_REVERB_APP_KEY} \
    VITE_REVERB_HOST=${VITE_REVERB_HOST} \
    VITE_REVERB_PORT=${VITE_REVERB_PORT} \
    VITE_REVERB_SCHEME=${VITE_REVERB_SCHEME}

RUN pnpm run build

###########################################
# Stage 3: Production image
###########################################
FROM serversideup/php:8.5-fpm-nginx AS production

LABEL org.opencontainers.image.title="Relaticle CRM"
LABEL org.opencontainers.image.description="Modern, open-source CRM platform"
LABEL org.opencontainers.image.source="https://github.com/Relaticle/relaticle"

# Switch to root to install dependencies
USER root

# Install required PHP extensions
RUN install-php-extensions intl exif gd imagick bcmath

# Install PostgreSQL client for health checks
RUN apt-get update \
    && apt-get install -y --no-install-recommends postgresql-client \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Switch back to www-data
USER www-data

WORKDIR /var/www/html

# Copy application source
COPY --chown=www-data:www-data . .

# Copy vendor from composer stage
COPY --chown=www-data:www-data --from=composer /app/vendor ./vendor

# Copy built frontend assets
COPY --chown=www-data:www-data --from=frontend /app/public/build ./public/build

# Generate optimized autoloader
RUN composer dump-autoload --optimize --no-dev

# Create storage directories
RUN mkdir -p \
    storage/app/public \
    storage/framework/cache/data \
    storage/framework/sessions \
    storage/framework/views \
    storage/logs \
    bootstrap/cache

# Default environment for serversideup/php Laravel automations
ENV AUTORUN_ENABLED=true
ENV AUTORUN_LARAVEL_STORAGE_LINK=true
ENV AUTORUN_LARAVEL_MIGRATION=true
ENV AUTORUN_LARAVEL_MIGRATION_ISOLATION=true
ENV AUTORUN_LARAVEL_CONFIG_CACHE=true
ENV AUTORUN_LARAVEL_ROUTE_CACHE=true
ENV AUTORUN_LARAVEL_VIEW_CACHE=true
ENV AUTORUN_LARAVEL_EVENT_CACHE=true
ENV AUTORUN_LARAVEL_OPTIMIZE=false
ENV PHP_OPCACHE_ENABLE=1
ENV SSL_MODE=off

# Refuse to start, loudly, when a required secret is missing: the guard's exit
# code aborts the container and the message lands in `docker compose logs`.
COPY --chmod=755 docker/prod/entrypoint.d/ /etc/entrypoint.d/

HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
    CMD curl -f http://localhost:8080/up || exit 1

EXPOSE 8080
