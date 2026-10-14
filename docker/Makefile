# Relaticle — shortcuts for the two Docker stacks in this directory.
#
#   make help
#
# Works from any directory: the recipes reference this file's location, not the
# caller's working directory. `docker/.env.dev` and `docker/.env.prod` are
# created from the .example files on first use.

DOCKER_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

DEV  := docker compose -f $(DOCKER_DIR)/compose.dev.yml --env-file $(DOCKER_DIR)/.env.dev
PROD := docker compose -f $(DOCKER_DIR)/compose.prod.yml --env-file $(DOCKER_DIR)/.env.prod

# Everything that touches the bind-mounted working tree runs as the image's
# www-data, which docker/dev/Dockerfile remaps to the host uid: files Pint
# rewrites, or artisan writes into storage/, must stay editable outside.
DEV_EXEC := $(DEV) exec -u www-data

.DEFAULT_GOAL := help

.PHONY: help dev-env dev-up dev-build dev-down dev-destroy dev-logs dev-shell \
        dev-artisan dev-migrate dev-seed dev-test dev-lint dev-assets dev-playwright \
        prod-env prod-build prod-up prod-down prod-logs prod-shell prod-artisan prod-status

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

# ─── Development ──────────────────────────────────────────────────────────────

dev-env: ## Create docker/.env.dev from the example (never overwrites)
	@test -f $(DOCKER_DIR)/.env.dev || cp $(DOCKER_DIR)/.env.dev.example $(DOCKER_DIR)/.env.dev

dev-up: dev-env ## Start the development stack (app, vite, queues, reverb, db, …)
	$(DEV) up -d --build

dev-build: dev-env ## Rebuild the development image (after editing docker/.env.dev)
	$(DEV) build --no-cache

dev-down: ## Stop the development stack (keeps volumes and the database)
	$(DEV) down

dev-destroy: ## Stop the development stack and delete its volumes (data goes away)
	$(DEV) down -v

dev-logs: ## Follow the logs of every development service
	$(DEV) logs -f --tail=100

dev-shell: ## Shell inside the app container
	$(DEV_EXEC) app bash

dev-artisan: ## Run an artisan command: make dev-artisan ARGS="route:list"
	$(DEV_EXEC) app php artisan $(ARGS)

dev-migrate: ## Run the migrations
	$(DEV_EXEC) app php artisan migrate --force

dev-seed: ## Seed the local personas (LocalSeeder — safe to repeat)
	$(DEV_EXEC) app php artisan db:seed --force

dev-test: ## Run the test suite, e.g. make dev-test ARGS="--filter=Company"
	$(DEV_EXEC) app php artisan test --compact $(ARGS)

dev-lint: ## Format PHP with Pint
	$(DEV_EXEC) app vendor/bin/pint --dirty

dev-assets: ## Build production assets (what a deployment would ship)
	$(DEV_EXEC) vite pnpm run build

dev-playwright: ## Install the Chromium browsers the Pest browser suite needs
	$(DEV_EXEC) app pnpm exec playwright install --with-deps chromium

# ─── Production ───────────────────────────────────────────────────────────────

prod-env: ## Create docker/.env.prod from the example (never overwrites)
	@test -f $(DOCKER_DIR)/.env.prod || cp $(DOCKER_DIR)/.env.prod.example $(DOCKER_DIR)/.env.prod

prod-build: prod-env ## Build the production image locally
	$(PROD) build

prod-up: prod-env ## Start (or update) the production stack
	$(PROD) up -d --build

prod-down: ## Stop the production stack (keeps volumes and the database)
	$(PROD) down

prod-logs: ## Follow the logs of every production service
	$(PROD) logs -f --tail=100

prod-shell: ## Shell inside the production app container
	$(PROD) exec app bash

prod-artisan: ## Run an artisan command: make prod-artisan ARGS="about"
	$(PROD) exec app php artisan $(ARGS)

prod-status: ## Show the state of the production services
	$(PROD) ps

# Like the image, this file is a resource for other operators: keep it honest.
