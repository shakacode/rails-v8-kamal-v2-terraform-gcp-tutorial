# Kamal v2 vs Control Plane: Deploying Rails 8 on GCP

This article compares two deployment paths for the same Rails 8 application: **Kamal v2 with Terraform** (DIY infrastructure) and **Control Plane** (managed container platform). Both approaches are fully configured in this repository so you can try them yourself.

## The Application

This is a standard Rails 8 app with:
- PostgreSQL database (4 databases: primary, cache, queue, cable)
- Solid Queue, Solid Cache, Solid Cable (no Redis needed)
- Thruster HTTP/2 proxy
- Importmaps + Propshaft (no Node.js build step)

## Side-by-Side Comparison

### Setup Complexity

| Aspect | Kamal v2 + Terraform | Control Plane (cpflow) |
|--------|---------------------|----------------------|
| Config files | `config/deploy.yml`, `.kamal/secrets`, `terraform-gcloud/*.tf` (~7 files) | `.controlplane/controlplane.yml` + templates (~8 files) |
| Prerequisites | GCP account, Terraform, Docker, domain name, Docker Hub account | Control Plane account, `cpln` CLI, Docker |
| Infrastructure provisioning | `terraform apply` (~10 min for Cloud SQL) | `cpflow setup-app` (~2 min) |
| First deploy | `terraform apply` + DNS setup + `kamal setup` (~15-20 min) | `cpflow setup-app` + `cpflow build-image` + `cpflow deploy-image` (~5-10 min) |
| Concepts to learn | Terraform, GCP Console, Cloud SQL, VMs, Docker, Kamal, DNS | Control Plane Console, cpflow commands, YAML templates |

### Infrastructure

| Aspect | Kamal v2 + Terraform | Control Plane |
|--------|---------------------|---------------|
| Compute | GCE VM (e2-small) you manage | Managed containers — no VMs |
| Database | Cloud SQL (managed by GCP, provisioned by Terraform) | Postgres workload (test) or external managed DB (production) |
| Networking | Static IP + firewall rules via Terraform | Managed by Control Plane |
| SSL | Let's Encrypt via kamal-proxy (auto-renewed) | Managed by Control Plane (automatic) |
| Load balancing | kamal-proxy on the VM | Built into Control Plane |
| Container registry | Docker Hub (or any registry) | Control Plane's built-in registry |

### Cost Comparison (Approximate Monthly)

| Resource | Kamal v2 + Terraform | Control Plane |
|----------|---------------------|---------------|
| Compute | GCE e2-small: ~$15/mo | Pay per vCPU/memory used |
| Database | Cloud SQL db-f1-micro: ~$10/mo | Postgres workload: included in compute, or external DB |
| Static IP | ~$3/mo (when attached) | Included |
| Docker Hub | Free tier or ~$5/mo | Built-in registry (included) |
| SSL certificate | Free (Let's Encrypt) | Free (included) |
| **Estimated total** | **~$25-30/mo** for a small app | **Varies** — can be lower or higher depending on usage |

Note: Control Plane pricing scales with actual resource consumption. For a small single-instance app, costs are comparable. The difference grows as you scale — Control Plane auto-scales down to zero when idle.

### Scaling

| Aspect | Kamal v2 + Terraform | Control Plane |
|--------|---------------------|---------------|
| Horizontal scaling | Manual: edit Terraform to add VMs, update `config/deploy.yml` | Automatic: set `minScale`/`maxScale` in template |
| Scale to zero | Not possible — VM always running | Supported — saves cost for low-traffic apps |
| Scale-up speed | Minutes (new VM provisioning) | Seconds (container spin-up) |
| Multi-region | Manual: duplicate Terraform per region | Built-in: add locations in `controlplane.yml` |
| Resource right-sizing | Choose VM size upfront | CapacityAI auto-adjusts CPU/memory |

### Day-to-Day Operations

| Operation | Kamal v2 | Control Plane (cpflow) |
|-----------|----------|----------------------|
| Deploy code | `bin/kamal deploy` | `cpflow build-image && cpflow deploy-image` |
| View logs | `bin/kamal logs` | `cpflow logs` |
| Rails console | `bin/kamal console` | `cpflow run -- rails console` |
| Shell access | `bin/kamal shell` | `cpflow run -- bash` |
| Rollback | `bin/kamal rollback` | Redeploy previous image |
| Maintenance mode | N/A (manual) | `cpflow maintenance:on` / `maintenance:off` |
| Review apps | Not built-in | `cpflow setup-app -a qa-app-pr-123` |
| DB migrations | Automatic via `bin/docker-entrypoint` | Automatic via `release_script.sh` |

### Multi-Cloud Flexibility

| Aspect | Kamal v2 + Terraform | Control Plane |
|--------|---------------------|---------------|
| Cloud providers | Any cloud with SSH access (rewrite Terraform per provider) | AWS, GCP, Azure — switch by changing `default_location` |
| Multi-cloud simultaneously | Requires separate Terraform configs per cloud | Native — add multiple locations in one config |
| Provider lock-in | Terraform is provider-specific (GCP modules here) | Cloud-agnostic — Control Plane abstracts the provider |

### Maintenance Burden

| Aspect | Kamal v2 + Terraform | Control Plane |
|--------|---------------------|---------------|
| OS updates | You patch the VM (apt upgrade, reboot) | Managed — no OS to patch |
| Docker updates | You update Docker on the VM | Managed |
| SSL renewal | Automatic (Let's Encrypt via kamal-proxy) | Automatic |
| Security patches | Monitor and apply to VM + Cloud SQL | Managed infrastructure |
| Monitoring | Set up yourself (disk, memory, CPU alerts) | Built-in metrics and alerting |
| Backups | Configure Cloud SQL backups via Terraform | Configure in workload templates or external DB |
| Disaster recovery | Rebuild from Terraform state | Redeploy to any location |

## Where Kamal Shines

1. **Simplicity and transparency** — Kamal is a thin wrapper around Docker and SSH. You can see every command it runs. There's no platform abstraction to debug through.

2. **Familiar tooling** — If you know Docker and SSH, you know Kamal. The `config/deploy.yml` is straightforward YAML.

3. **Low cost floor** — A single small VM (~$15/mo) runs your entire app. No platform fees or per-request pricing.

4. **Full control** — You own the VM. SSH in anytime. Install whatever you need. No platform restrictions.

5. **Works anywhere** — Any server with SSH and Docker works. Bare metal, any cloud, even a Raspberry Pi.

6. **DHH-endorsed** — Ships with Rails 8 by default. Strong community and Rails-aligned philosophy.

## Where Control Plane Shines

1. **No VM management** — No SSH, no OS patching, no disk space monitoring, no Docker daemon maintenance. You deploy containers; Control Plane runs them.

2. **Auto-scaling** — Scale from zero to many replicas based on load. Pay only for what you use. Kamal requires manual VM sizing and can't scale to zero.

3. **Multi-cloud deployment** — Deploy to AWS, GCP, and Azure simultaneously from the same config. With Kamal, each cloud requires separate Terraform configuration.

4. **Built-in review apps** — `cpflow setup-app -a qa-app-pr-123` creates a full environment in minutes. Kamal has no built-in equivalent.

5. **Managed infrastructure** — SSL, load balancing, container registry, networking, and health checks are all handled by the platform.

6. **Simpler secrets management** — Secrets are managed through the Control Plane console or API. No need for GCP Secret Manager, 1Password, or other external tools.

7. **Production promotion** — Promote a tested staging image directly to production without rebuilding. `cpflow promote-app-from-upstream` copies the exact image.

8. **Maintenance mode** — Built-in `cpflow maintenance:on/off` with a customizable maintenance page. Kamal requires manual setup.

## When to Choose Which

**Choose Kamal v2 + Terraform when:**
- You want full control over your infrastructure
- You're comfortable managing VMs and enjoy understanding every layer
- Your app runs on a single server and doesn't need auto-scaling
- You want the lowest possible monthly cost for a small app
- You prefer the "Rails Way" default deployment tool

**Choose Control Plane when:**
- You don't want to manage VMs, OS updates, or Docker daemons
- You need auto-scaling (especially scale-to-zero for cost savings)
- You want multi-cloud or multi-region deployment
- You need review apps for every PR
- You want a Heroku-like experience with more flexibility
- Your team's time is more valuable than the platform cost

## Try Both

This repository has both deployment paths fully configured:

- **Kamal path**: See the main [README.md](../README.md) and `config/deploy.yml`
- **Control Plane path**: See [.controlplane/readme.md](../.controlplane/readme.md) and `.controlplane/controlplane.yml`

Deploy the same app both ways and decide which fits your team best.
