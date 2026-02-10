# Deploying Changes

This guide covers the two main deployment workflows: pushing code changes and modifying infrastructure.

## Code Changes (Kamal Deploy)

Use this workflow when you change application code, gems, assets, or configuration — anything that affects the Docker image but not the GCP infrastructure.

### Steps

1. **Make your changes and commit:**

   ```bash
   git add -A && git commit -m "Your change description"
   ```

2. **Deploy:**

   ```bash
   ./bin/kamal deploy
   ```

   This will:
   - Clone the repo at the current commit into a temp directory
   - Build a Docker image (with layer caching — only changed layers rebuild)
   - Push the image to Docker Hub
   - Pull the image on the server
   - Start a new container with the new image
   - Health-check the new container via kamal-proxy (`GET /up` on port 80)
   - Route traffic to the new container
   - Stop and remove the old container

3. **Verify:**

   ```bash
   # Check containers and proxy status
   ./bin/kamal details

   # Tail logs
   ./bin/kamal logs

   # Or visit your site
   curl -sk https://gcp.kamaltutorial.com/up
   ```

### What Gets Cached

Docker layer caching makes subsequent deploys much faster than the initial one:

| Layer | Rebuilds When | Typical Time |
|-------|--------------|--------------|
| Base image (Ruby slim) | Ruby version changes | ~0s (cached) |
| System packages (`apt-get`) | Dockerfile `RUN apt-get` line changes | ~0s (cached) |
| Gems (`bundle install`) | Gemfile or Gemfile.lock changes | ~60-300s |
| App code (`COPY . .`) | Any file changes | ~1s |
| Bootsnap precompile | App/lib code changes | ~2s |
| Asset precompile | CSS/JS/view changes | ~5-10s |

A code-only change (no gem changes) typically builds in under 30 seconds, plus ~15-30 seconds for push/pull/health-check.

### Important Notes

- **Kamal deploys the committed code**, not your working directory. Always commit before deploying.
- **Two containers run simultaneously** during deploy (old + new). The instance needs enough RAM for both. An `e2-small` (2 GB) is the minimum; `e2-micro` (1 GB) will likely cause the instance to become unresponsive during deploys. See [troubleshooting.md](troubleshooting.md#instance-sizing) for details.
- **Database migrations** run automatically via `bin/docker-entrypoint`, which calls `rails db:prepare` on startup.
- The `deploy_timeout` in `config/deploy.yml` (default: 120 seconds) controls how long kamal-proxy waits for the new container to become healthy.

## Infrastructure Changes (Terraform + Kamal)

Use this workflow when you need to change GCP resources: instance size, database configuration, firewall rules, startup scripts, etc.

### Workflow Overview

```text
Edit terraform-gcloud/*.tf → terraform plan → terraform apply → (optional) kamal deploy
```

Whether you need a Kamal redeploy after `terraform apply` depends on what changed.

### Changes That Do NOT Require Kamal Redeploy

These Terraform changes take effect without redeploying the app:

- **Firewall rules** — applied at the network level
- **IAM bindings** — permissions update immediately
- **Cloud SQL settings** — database changes are independent of the app container

### Changes That Require Instance Restart (Causes Downtime)

- **Machine type** (e.g., `e2-micro` → `e2-small`) — Terraform stops the instance, changes the type, and restarts it. After restart, Docker auto-starts containers with `--restart unless-stopped`, so the app should come back up automatically. The static IP (`google_compute_address`) ensures the IP stays the same — no need to update `config/deploy.yml` or DNS.

- **Boot disk image** — requires instance recreation (Terraform will destroy and recreate). The static IP is preserved since it's a separate resource.

### Changes That Require Kamal Redeploy

- **Startup script changes** — the startup script only runs on first boot (or after instance recreation). If you change it and need it re-applied, you'll need to recreate the instance or manually apply the changes via SSH.

- **Environment variable changes in `config/deploy.yml`** — these are baked into the container at deploy time.

### Steps

1. **Edit the Terraform files:**

   ```bash
   # Example: upgrade instance size
   # In terraform-gcloud/main.tf, change:
   #   machine_type = "e2-micro"
   # to:
   #   machine_type = "e2-small"
   ```

2. **Preview the changes:**

   ```bash
   cd terraform-gcloud
   terraform plan
   ```

   Read the plan carefully. Look for:
   - `~ update in-place` — modifies the resource (usually safe)
   - `-/+ destroy and then create` or `+/- create and then destroy` — **recreates** the resource (causes downtime for compute instances, data loss for databases without backups)

3. **Apply the changes:**

   ```bash
   terraform apply
   ```

   Type `yes` to confirm.

4. **If the instance was restarted or recreated**, wait 2-3 minutes for the startup script to finish, then verify:

   ```bash
   # Check instance status
   gcloud compute instances describe rails-app-instance \
     --zone=us-central1-a --format="value(status)"

   # Verify SSH works
   ssh your-username@YOUR_INSTANCE_IP

   # On the server, check Docker is running
   docker ps
   ```

5. **If a Kamal redeploy is needed:**

   ```bash
   ./bin/kamal deploy
   ```

### Common Infrastructure Changes

#### Upgrading Instance Size

If you need more resources (e.g., upgrading from `e2-small` to `e2-medium` for a larger app):

```terraform
# terraform-gcloud/main.tf
resource "google_compute_instance" "rails_app" {
  machine_type = "e2-medium" # was "e2-small"
}
```

```bash
cd terraform-gcloud
terraform plan   # Will show: ~ update in-place (instance must be stopped)
terraform apply  # Terraform stops, resizes, and restarts the instance
```

**Downtime:** Yes, typically 1-2 minutes while the instance stops and restarts. Docker containers auto-restart after reboot. The `allow_stopping_for_update = true` setting in the Terraform config permits Terraform to stop the instance for this change. The static IP ensures `config/deploy.yml` and DNS remain valid.

**Tip:** After major gem or framework upgrades, monitor memory during deploys with `docker stats --no-stream` on the server. If the instance becomes unresponsive during deploys, it's a sign you need a larger instance.

#### Changing Cloud SQL Proxy Version

Update the version in the startup script in `main.tf`:

```terraform
wget -q https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.22.0/cloud-sql-proxy.linux.amd64 ...
```

Since the startup script only runs on first boot, you'll need to either:
- Recreate the instance (via `terraform taint google_compute_instance.rails_app` then `terraform apply`)
- Or SSH in and manually update: download the new binary, restart the systemd service

#### Changing Database Tier

```terraform
# terraform-gcloud/main.tf
resource "google_sql_database_instance" "rails_db_instance" {
  settings {
    tier = "db-g1-small" # was "db-f1-micro"
  }
}
```

This restarts the Cloud SQL instance (brief database downtime) but does not affect the compute instance or app containers.

## Full Teardown and Rebuild

If you want to start fresh:

```bash
# Graceful teardown
terraform-gcloud/bin/tear-down

# Full rebuild
terraform-gcloud/bin/stand-up
```

See the [README](../README.md#automated-deployment) for details on what these scripts do.
