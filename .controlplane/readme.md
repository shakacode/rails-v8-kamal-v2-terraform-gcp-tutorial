# Deploying on Control Plane

_If you need a free demo account for Control Plane (no CC required), you can contact [Justin Gordon, CEO of ShakaCode](mailto:justin@shakacode.com)._

## Overview

This directory contains everything needed to deploy the Rails 8 tutorial app to [Control Plane](https://controlplane.com) using the [`cpflow` gem](https://github.com/shakacode/control-plane-flow).

This is an alternative deployment path to the Kamal v2 + Terraform approach in the main repo. See [Kamal vs Control Plane comparison](../docs/kamal-vs-control-plane.md) for a detailed side-by-side analysis.

### Key Differences from Kamal Deployment

| Aspect | Kamal | Control Plane |
|--------|-------|---------------|
| Infrastructure | Terraform + GCE VM | Managed by Control Plane |
| Container orchestration | Kamal CLI + Docker | Control Plane platform |
| Scaling | Manual (resize VM) | Auto-scaling built-in |
| SSL | Let's Encrypt via kamal-proxy | Managed by Control Plane |
| Database | Cloud SQL + Proxy | Postgres workload (test) or external |
| Redis | Not needed (Solid*) | Not needed (Solid*) |

## Prerequisites

1. **Control Plane account** — Set up at [shakacode.controlplane.com](https://shakacode.controlplane.com). Set `CPLN_ORG` env var to your organization name, or edit `cpln_org` in `controlplane.yml`.
   If you need an organization, [contact ShakaCode](mailto:controlplane@shakacode.com).

2. **Control Plane CLI** — Install with `npm install -g @controlplane/cli`, then run `cpln login`.

3. **Docker registry access** — Run `cpln image docker-login --org <your-org>`.

4. **cpflow gem** — Install globally with `gem install cpflow`. (Not in the Gemfile due to a thor version conflict with Rails 8's solid_queue.)

5. **Docker** — Ensure Docker is running locally.

### Tips

Do not confuse `cpflow` (the deployment CLI from ShakaCode) with `cpln` (the Control Plane CLI).

## Project Configuration

| File | Purpose |
|------|---------|
| `controlplane.yml` | App definitions, organization, location, workload configuration |
| `Dockerfile` | Docker image for the Rails app (simpler than main Dockerfile — no Node.js needed) |
| `entrypoint.sh` | Container entrypoint — waits for Postgres before starting |
| `release_script.sh` | Runs `rails db:prepare` during release phase |
| `templates/` | YAML templates for Control Plane resources |

### Templates

| Template | Purpose |
|----------|---------|
| `app.yml` | GVC (app) definition with env vars and identity |
| `rails.yml` | Rails web workload (like a Heroku web dyno) |
| `postgres.yml` | Stateful Postgres workload for test/QA apps |
| `maintenance.yml` | Maintenance mode workload |

## Setup and Deploy

Check that the Control Plane organization and location are correct in `controlplane.yml`.

```sh
# Set app name for convenience
export APP_NAME=rails-kamal-demo-staging

# Provision all infrastructure on Control Plane
cpflow setup-app -a $APP_NAME

# Build and push Docker image to Control Plane registry
# This may take several minutes on first build
cpflow build-image -a $APP_NAME

# Deploy the image to the app
cpflow deploy-image -a $APP_NAME

# Watch logs as the app starts up
cpflow logs -a $APP_NAME

# Open app in browser
cpflow open -a $APP_NAME
```

## Deploying Code Updates

```sh
# Build and push new image with sequential tagging
cpflow build-image -a $APP_NAME

# Deploy latest image (runs release_script.sh for DB migrations)
cpflow deploy-image -a $APP_NAME
```

## Common Operations

```sh
# Run a one-off command (like heroku run)
cpflow run -a $APP_NAME -- rails console

# Check running replicas
cpflow ps -a $APP_NAME

# Enable maintenance mode
cpflow maintenance:on -a $APP_NAME

# Disable maintenance mode
cpflow maintenance:off -a $APP_NAME

# Delete the app entirely
cpflow delete -a $APP_NAME
```

## QA / Review Apps

Create a review app for a pull request:

```sh
cpflow setup-app -a qa-rails-kamal-demo-pr-1234
cpflow build-image -a qa-rails-kamal-demo-pr-1234
cpflow deploy-image -a qa-rails-kamal-demo-pr-1234
```

Clean up when done:

```sh
cpflow delete -a qa-rails-kamal-demo-pr-1234
```

## Production Promotion

Promote the staging image to production (no rebuild needed):

```sh
cpflow promote-app-from-upstream -a rails-kamal-demo-production -t $UPSTREAM_TOKEN
```

## Rails 8 Notes

This app uses Rails 8's Solid adapters (Solid Queue, Solid Cache, Solid Cable) instead of Redis. This means:

- **No Redis workload needed** — fewer resources to manage
- **Solid Queue runs in Puma** — set via `SOLID_QUEUE_IN_PUMA=true` in `app.yml`
- **4 databases** — primary, cache, queue, cable — all created by `rails db:prepare`
- **Thruster** — HTTP/2 proxy used as the default CMD for optimized performance
