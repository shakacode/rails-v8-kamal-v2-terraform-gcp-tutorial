# CLAUDE.md

## Project Overview

Rails 8 tutorial app demonstrating deployment to Google Cloud Platform using Kamal v2 for container orchestration and Terraform for infrastructure-as-code. The app itself is a simple Rails demo; the value is in the deployment automation.

## Architecture

```
terraform-gcloud/bin/stand-up
  -> lib/kamal_deployment_manager.rb (orchestrator)
    -> terraform init/apply (provisions GCP infra)
    -> updates config/deploy.yml with new IP
    -> verifies DNS resolution via Google DNS (8.8.8.8)
    -> runs kamal setup (builds Docker image, deploys)

terraform-gcloud/bin/tear-down
  -> kamal app stop
  -> terraform destroy (--keep-ip flag preserves static IP)
```

### Key Files

| File | Purpose |
|------|---------|
| `lib/kamal_deployment_manager.rb` | Core deployment orchestrator — called by stand-up and bin/kamal |
| `config/deploy.yml` | Kamal v2 config (server IP, registry, secrets, proxy) |
| `terraform-gcloud/main.tf` | All GCP infrastructure (Compute Engine, Cloud SQL, firewall, static IP) |
| `terraform-gcloud/variables.tf` | Terraform inputs: `project_id`, `ssh_user` |
| `terraform-gcloud/outputs.tf` | Terraform outputs: `instance_ip`, db connection info |
| `.kamal/secrets` | Sources secrets from GCP Secret Manager via `gcloud` CLI |
| `bin/kamal` | Wrapper that validates deployed IP matches configured IP before running kamal |

### How Secrets Work

`.kamal/secrets` runs `gcloud secrets versions access` to fetch three secrets from GCP Secret Manager:
- `KAMAL_REGISTRY_PASSWORD` — Docker Hub credentials
- `DB_PASSWORD` — PostgreSQL password
- `SECRET_KEY_BASE` — Rails secret key

These are referenced in `config/deploy.yml` under `env.secret` and `registry.password`.

### Networking

- Docker containers reach the host machine (and Cloud SQL Proxy) via `172.18.0.1` (DB_HOST in deploy.yml)
- Cloud SQL Proxy runs as a systemd service on the GCP instance, listening on port 5432
- The proxy is installed via the instance's `metadata_startup_script` in `main.tf`

## Machine-Managed Files — Do Not Edit Manually

- **`config/deploy.yml` server IP** (`servers.web[0]`) — Updated automatically by `lib/kamal_deployment_manager.rb` during stand-up. The IP comes from `terraform output instance_ip`.
- **`config/deploy.yml` deploy_timeout** — Temporarily increased to 120s during stand-up for initial `rails db:prepare`, then restored to the original value.
- **`terraform-gcloud/terraform-state/`** — Gitignored. Never commit terraform state files.

## Commands

### Development
```bash
bin/setup          # Install gems, prepare database
bin/dev            # Start dev server (Foreman + Procfile.dev)
bin/rails server   # Start Rails only
```

### Testing and Linting
```bash
bundle exec rake test           # Run tests
bundle exec rubocop             # Run linter (always use bundle exec)
bundle exec rubocop -a          # Autofix lint issues
bundle exec brakeman            # Security scan
```

### Deployment (production)
```bash
terraform-gcloud/bin/stand-up   # Full automated deploy (terraform + kamal)
terraform-gcloud/bin/tear-down  # Destroy all infrastructure
terraform-gcloud/bin/tear-down --keep-ip  # Destroy but preserve static IP (~$0.01/hr)
bin/kamal deploy                # Deploy code changes (after initial setup)
bin/kamal console               # Rails console on production
bin/kamal logs                  # Tail production logs
```

### Terraform (manual)
```bash
cd terraform-gcloud && terraform init    # Initialize providers
cd terraform-gcloud && terraform plan    # Preview changes
cd terraform-gcloud && terraform apply   # Apply changes
cd terraform-gcloud && terraform output  # Show outputs (instance_ip, etc.)
```

## Important Gotchas

1. **`bin/kamal` is a wrapper, not the raw gem.** It validates that the deployed IP (from terraform output) matches the IP in `config/deploy.yml` before running any kamal command. If they don't match, it aborts with a message to re-run `stand-up`.

2. **`ssh_user` must match in two places:** `terraform-gcloud/variables.tf` (`ssh_user` default) and `config/deploy.yml` (`ssh.user`). If these diverge, SSH connections will fail.

3. **Instance sizing matters.** `e2-small` (2 GB RAM) is the minimum for reliable Kamal deploys. `e2-micro` (1 GB) causes resource exhaustion when old and new containers run simultaneously during zero-downtime deploys.

4. **First deploy may timeout.** `rails db:prepare` runs schema creation on initial deploy, which can exceed the default timeout. The stand-up script handles this by temporarily setting `deploy_timeout: 120`. If deploying manually, increase the timeout or just run `bin/kamal deploy` again.

5. **SSL certificate timing.** After a fresh deploy, Chrome may show `ERR_CERTIFICATE_TRANSPARENCY_REQUIRED` for 5-10 minutes while Let's Encrypt CT logs propagate. This is not a configuration error. Try an incognito window first — Chrome caches SSL state aggressively.

6. **Static IP import.** When `tear-down --keep-ip` was used previously, `stand-up` automatically imports the preserved static IP into Terraform state so DNS and deploy.yml stay stable.

7. **DNS verification uses Google DNS (8.8.8.8)** to bypass local caching. If DNS isn't resolving, check the registrar — the A record name should be the subdomain only (e.g., `gcp`), not the full hostname.

8. **Kamal lock files.** If a deploy is interrupted, it may leave a lock. Release with `bin/kamal lock release`.
