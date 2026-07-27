#!/bin/bash -e

# Entrypoint script for Control Plane deployment.
# Waits for Postgres to be available before running the main command.

wait_for_service()
{
  local retries=0
  local max_retries=30
  until curl -I -sS "$1" 2>&1 | grep -q "Empty reply from server"; do
    echo " -- $1 is unavailable, sleeping..."
    sleep 1
    retries=$((retries + 1))
    if [ "$retries" -ge "$max_retries" ]; then
      echo " -- ERROR: $1 did not become available after ${max_retries}s"
      exit 1
    fi
  done
  echo " -- $1 is available"
}

echo " -- Starting entrypoint.sh"

# Wait for Postgres if DATABASE_URL is set
if [ -n "$DATABASE_URL" ]; then
  echo " -- Waiting for Postgres"
  wait_for_service "$(echo "$DATABASE_URL" | sed -e 's|^.*@||' -e 's|/.*$||')"
fi

echo " -- Finishing entrypoint.sh, executing '$*'"

# Run the main command
exec "$@"
