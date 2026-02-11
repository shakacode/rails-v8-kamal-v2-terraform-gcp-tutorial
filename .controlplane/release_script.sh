#!/bin/bash -e

log() {
    echo "[$(date +%Y-%m-%d:%H:%M:%S)]: $1"
}

error_exit() {
    log "$1" 1>&2
    exit 1
}

log 'Running release_script.sh per controlplane.yml'

# Validate SECRET_KEY_BASE is not a placeholder in production
if [ "$RAILS_ENV" = "production" ]; then
    if [ -z "$SECRET_KEY_BASE" ] || [ "$SECRET_KEY_BASE" = "placeholder_secret_key_base_for_test_apps_only" ] || [ "$SECRET_KEY_BASE" = "precompile_placeholder" ]; then
        error_exit "SECRET_KEY_BASE must be set to a secure value in production. Generate one with: openssl rand -hex 64"
    fi
fi

if [ -x ./bin/rails ]; then
    log 'Run DB migrations (all 4 databases: primary, cache, queue, cable)'
    SECRET_KEY_BASE="${SECRET_KEY_BASE:-precompile_placeholder}" ./bin/rails db:prepare || error_exit "Failed to run DB migrations"
else
    error_exit "./bin/rails does not exist or is not executable"
fi

log 'Completed release_script.sh per controlplane.yml'
