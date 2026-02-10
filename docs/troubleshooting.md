# Troubleshooting Kamal Deploys on GCP

This guide covers common issues when deploying with Kamal to a GCP Compute Engine instance, based on real production debugging sessions.

## Instance Sizing

The Terraform configuration uses `e2-small` (0.5 shared vCPU, 2 GB RAM). The instance runs several processes concurrently:

- **Docker daemon** + containerd
- **kamal-proxy** (reverse proxy with TLS termination)
- **Cloud SQL Proxy** (database connectivity)
- **Rails app container** (Puma + Solid Queue)
- **GCP system agents** (guest agent, OS config agent)

During a Kamal deploy, **two app containers run simultaneously** (old + new) for zero-downtime deployment. This temporarily doubles the app's memory footprint.

### Why Not e2-micro?

The `e2-micro` (0.25 vCPU, 1 GB RAM) may seem attractive for a tutorial, but it cannot reliably handle Kamal's zero-downtime deploys. When two Rails containers run simultaneously during the deploy handoff, the instance becomes completely unresponsive — no SSH, no health checks, no metadata service. The deploy appears stuck, and recovering requires a hard reset via `gcloud compute instances reset`.

This issue may not appear on the initial deploy but can surface after gem or framework upgrades increase memory usage. For example, upgrading to Rails 8.0.4 with Puma 7 and updated dependencies pushed memory requirements past what e2-micro could handle during deploys.

### Recommended Instance Sizes

| Instance Type | vCPU | RAM   | Monthly Cost* | Suitable For                        |
|---------------|------|-------|---------------|-------------------------------------|
| `e2-micro`    | 0.25 | 1 GB  | ~$7           | Too small for Kamal deploys         |
| `e2-small`    | 0.5  | 2 GB  | ~$14          | Minimum for reliable deploys        |
| `e2-medium`   | 1    | 4 GB  | ~$27          | Comfortable for production use      |

*Approximate us-central1 pricing. Use the [GCP Pricing Calculator](https://cloud.google.com/products/calculator) for exact costs.

### Changing Instance Size

Edit `terraform-gcloud/main.tf`:

```terraform
resource "google_compute_instance" "rails_app" {
  machine_type = "e2-small" # Minimum for reliable Kamal deploys
}
```

Then apply: `cd terraform-gcloud && terraform apply`

**Note:** Changing machine type requires the instance to be stopped and restarted, which will cause brief downtime. Docker containers auto-restart after reboot.

**Gotcha:** If `terraform apply` fails with `please set allow_stopping_for_update = true`, the Terraform config is missing the flag that permits Terraform to stop a running instance. This is already set in the project's `main.tf`, but if you're adapting this for your own project, make sure to include it:

```terraform
resource "google_compute_instance" "rails_app" {
  allow_stopping_for_update = true
  # ...
}
```

## Deploy Stuck at Health Check

### Symptoms

`bin/kamal deploy` hangs at the kamal-proxy deploy step:

```
INFO Running docker exec kamal-proxy kamal-proxy deploy rails_kamal_demo-web
  --target="<container_id>:80" --deploy-timeout="120s" ...
```

This means kamal-proxy is health-checking the new container (hitting `/up` on port 80) and not getting a healthy response within the `deploy_timeout` (default: 120 seconds).

### Common Causes

1. **Instance out of resources** — Two containers running simultaneously on an undersized instance (see [Instance Sizing](#instance-sizing) above)
2. **App crashing on boot** — Missing env var, migration error, or code error in production
3. **Database unreachable** — Cloud SQL Proxy not running or misconfigured
4. **Port mismatch** — App not listening on the expected port

### Debugging Steps

If the deploy is stuck but SSH still works:

```bash
# SSH into the instance
ssh your-username@YOUR_INSTANCE_IP

# Check container status
docker ps -a

# Check the NEW container's logs (most important)
docker logs <new_container_name> --tail 100

# Check kamal-proxy health check results
docker logs kamal-proxy --tail 50

# Test the health endpoint directly
docker exec <new_container_name> curl -s http://localhost:80/up
```

## SSH Not Responding

### Symptoms

- `ssh user@ip` hangs indefinitely
- `bin/kamal` commands hang with no output after "Running ... on <ip>"
- Kamal throws `Net::SSH::Disconnect: connection closed by remote host`

### Cause

The instance is likely resource-exhausted. All services (including the SSH daemon) are starved of CPU/memory. This commonly happens on `e2-micro` instances during deploys.

### Recovery

**Step 1: Check instance status from your local machine:**

```bash
gcloud compute instances describe rails-app-instance \
  --zone=us-central1-a --project=YOUR_PROJECT_ID \
  --format="value(status)"
```

**Step 2: View the serial console (doesn't require SSH):**

```bash
gcloud compute instances get-serial-port-output rails-app-instance \
  --zone=us-central1-a --project=YOUR_PROJECT_ID
```

Look for:
- `oom-kill` or `Out of memory` — OOM killer terminated processes
- `context deadline exceeded` — services timing out due to resource starvation
- `dial tcp 169.254.169.254:80: i/o timeout` — metadata service unreachable (severe resource exhaustion)

**Step 3: Reset the instance:**

```bash
gcloud compute instances reset rails-app-instance \
  --zone=us-central1-a --project=YOUR_PROJECT_ID
```

Wait 2-3 minutes for the startup script to complete (it installs Docker and starts Cloud SQL Proxy), then SSH in.

**Step 4: Immediately clean up after reset:**

After the instance reboots, Docker restarts all containers with `--restart unless-stopped` policy — including both the old and new app containers. Remove the extra container quickly to prevent another resource exhaustion:

```bash
ssh your-username@YOUR_INSTANCE_IP

# See what's running
docker ps -a

# Stop and remove the extra app container
docker stop <unwanted_container_name>
docker rm <unwanted_container_name>
```

**Step 5: Release the deploy lock and redeploy:**

The stuck deploy left a lock file on the server. Release it from your local machine before redeploying:

```bash
bin/kamal lock release
bin/kamal deploy
```

## Kamal Deploy Lock Stuck

### Symptoms

```
ERROR (Kamal::Cli::LockError): Deploy lock found. Run 'kamal lock help' for more information
```

The error message includes who acquired the lock, when, and which version was being deployed. This commonly happens after a stuck or interrupted deploy — the lock was never released because the deploy process didn't complete cleanly.

### Fix

**From your local machine** (preferred — works if SSH to the server is functional):

```bash
bin/kamal lock release
```

Then retry your deploy:

```bash
bin/kamal deploy
```

**From the server** (if Kamal commands are hanging):

```bash
ssh your-username@YOUR_INSTANCE_IP
rm -f .kamal/lock
```

**Important:** After recovering from a stuck deploy (instance reset, Ctrl-C, etc.), always release the deploy lock before attempting to redeploy.

## Fixing kamal-proxy Routing After Recovery

After a reset or manual container cleanup, kamal-proxy may still target a removed container, causing 502 errors.

### Diagnosis

```bash
# On the server, check what kamal-proxy is targeting
docker exec kamal-proxy kamal-proxy list
```

If the target container no longer exists, you'll get 502 Bad Gateway responses.

### Fix

The simplest fix is to redeploy from your local machine:

```bash
bin/kamal deploy
```

Alternatively, manually re-point kamal-proxy to a running container:

```bash
# On the server, find the running app container
docker ps --filter label=service=rails_kamal_demo

# Re-point kamal-proxy (replace CONTAINER_ID with the actual container ID)
docker exec kamal-proxy kamal-proxy deploy rails_kamal_demo-web \
  --target="CONTAINER_ID:80" \
  --host="gcp.kamaltutorial.com" \
  --tls
```

## Cloud SQL Proxy Issues

### Symptoms

App logs show:

```
ActiveRecord::DatabaseConnectionError There is an issue connecting with your hostname: 172.18.0.1
```

### Debugging

```bash
# On the server, check if Cloud SQL Proxy is running
systemctl status cloud-sql-proxy

# Check Cloud SQL Proxy logs
journalctl -u cloud-sql-proxy --no-pager -n 50

# Verify port 5432 is listening
ss -tlnp | grep 5432

# Test connectivity from a container
docker exec <app_container> bash -c "pg_isready -h 172.18.0.1 -p 5432"
```

If Cloud SQL Proxy shows `failed to connect to instance: context deadline exceeded`, the instance was likely overloaded. After a reset, it should reconnect automatically.

## Useful Debugging Commands

### Local (from your machine)

```bash
# Check instance status
gcloud compute instances describe rails-app-instance \
  --zone=us-central1-a --format="value(status)"

# View serial console output
gcloud compute instances get-serial-port-output rails-app-instance \
  --zone=us-central1-a

# Reset instance (hard reboot)
gcloud compute instances reset rails-app-instance --zone=us-central1-a

# SSH via gcloud (alternative if regular SSH fails)
gcloud compute ssh YOUR_USER@rails-app-instance --zone=us-central1-a

# Kamal status commands
bin/kamal details
bin/kamal app containers
bin/kamal proxy logs
```

### On the server (via SSH)

```bash
# Container status
docker ps -a
docker stats --no-stream

# App logs
docker logs <container_name> --tail 100

# kamal-proxy logs and routing
docker logs kamal-proxy --tail 50
docker exec kamal-proxy kamal-proxy list

# System resources
free -h
top -bn1 | head -20

# Cloud SQL Proxy
systemctl status cloud-sql-proxy
journalctl -u cloud-sql-proxy --no-pager -n 20
```
