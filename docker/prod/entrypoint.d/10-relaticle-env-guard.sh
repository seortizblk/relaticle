#!/bin/sh
#
# Relaticle — production environment guard.
#
# serversideup/php runs /etc/entrypoint.d/*.sh before s6 starts the services and
# aborts the container when a script exits non-zero, so a missing secret is a
# startup failure with a message in `docker compose logs` instead of a 500 the
# first time somebody opens the sign-in page.
#
# Runs in every container of the production stack; the checks are read-only.

set -u

missing=""

if [ -z "$(printenv APP_KEY 2>/dev/null || true)" ]; then
    missing="${missing} APP_KEY"
fi

if [ -z "$(printenv DB_PASSWORD 2>/dev/null || true)" ]; then
    missing="${missing} DB_PASSWORD"
fi

if [ -n "$missing" ]; then
    echo "❌ relaticle: missing required environment variable(s):${missing}" >&2
    echo "   Fill in docker/.env.prod (see docker/.env.prod.example) and start again." >&2
    echo "   APP_KEY:      php -r 'echo \"base64:\".base64_encode(random_bytes(32)), PHP_EOL;'" >&2
    exit 1
fi

if [ "$(printenv BROADCAST_CONNECTION 2>/dev/null || true)" = "reverb" ]; then
    if [ -z "$(printenv REVERB_APP_KEY 2>/dev/null || true)" ]; then
        echo "⚠️  relaticle: BROADCAST_CONNECTION=reverb without REVERB_APP_KEY — realtime (chat streaming) will not work." >&2
    fi

    case "$(printenv REVERB_HOST 2>/dev/null || true)" in
        ""|localhost|127.0.0.1)
            echo "⚠️  relaticle: REVERB_HOST is '$(printenv REVERB_HOST 2>/dev/null || true)' — browsers will try to open the WebSocket against themselves." >&2
            echo "   Set it to the public host that reaches this stack (e.g. crm.example.com)." >&2
            ;;
    esac
fi
