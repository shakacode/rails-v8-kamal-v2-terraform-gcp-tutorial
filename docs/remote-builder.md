# Remote Docker Builder for Apple Silicon Macs

Building Docker images for `linux/amd64` on Apple Silicon (M1/M2/M3/M4) Macs requires QEMU emulation, which makes the first build extremely slow (20-30 minutes). You can skip this entirely by using your GCP Compute Engine instance as a remote Docker builder.

Since the Terraform setup already provisions an amd64 Linux instance with Docker installed, **no additional infrastructure is needed** — your app server doubles as the build server.

## How It Works

Kamal uses [Docker buildx](https://docs.docker.com/build/builders/) under the hood. When you configure a `remote` builder, Kamal creates a buildx builder that connects to the remote machine via SSH, runs the Docker build there natively (no emulation), and pushes the resulting image to your registry.

```
┌─────────────────┐     SSH      ┌──────────────────────┐     Push     ┌─────────────┐
│  Your Mac       │ ──────────► │  GCP Instance         │ ──────────► │  Docker Hub  │
│  (ARM, kamal)   │  build ctx  │  (amd64, Docker)      │    image    │  (registry)  │
└─────────────────┘             └──────────────────────┘             └─────────────┘
```

## Prerequisites

These are already satisfied by the Terraform setup in this project:

1. **SSH access** to the GCP instance (`ssh justin@<SERVER_IP>` works)
2. **Docker installed** on the instance (installed by the Terraform startup script)
3. **Your SSH user in the `docker` group** (configured by the Terraform startup script)

Verify with:
```bash
# Confirm SSH works
ssh justin@<SERVER_IP> "docker version"
```

You should see Docker server info with `linux/amd64` as the platform.

## Setup

### 1. Update `config/deploy.yml`

Uncomment and configure the `remote` line in the `builder` section:

```yaml
builder:
  arch: amd64
  args:
    GIT_REVISION: "<%= `git rev-parse HEAD`.strip %>"
    BUILD_TIME: "<%= Time.now.utc.iso8601 %>"

  # Use the GCP instance as a remote amd64 builder (avoids slow QEMU emulation on ARM Macs)
  remote: ssh://justin@<SERVER_IP>
```

Replace `<SERVER_IP>` with your instance IP (e.g., `34.29.79.152`) and `justin` with your SSH user.

### 2. Deploy

Run the deploy as usual:

```bash
./bin/kamal setup   # first time
./bin/kamal deploy  # subsequent deploys
```

Kamal automatically:
1. Creates a Docker buildx builder that uses the remote machine
2. Sends the build context (your project files) over SSH
3. Runs the multi-stage Docker build natively on amd64
4. Pushes the image to Docker Hub from the remote machine

### 3. Verify

You'll see output like this during the build step:

```
Building with remote builder on ssh://justin@34.29.79.152...
```

The first remote build takes about 3-5 minutes (same as a native Linux build) instead of 20-30 minutes with QEMU.

## Expected Build Times

| Scenario | Local on ARM Mac | Remote on GCP instance |
|----------|-----------------|----------------------|
| Fresh build (no Docker cache) | 20-30 min | 3-5 min |
| Incremental (Ruby code only) | 3-5 min | 1-2 min |
| Gemfile changes | 10-15 min | 2-3 min |

## Important Notes

### Resource Usage

The `e2-small` instance (0.5 vCPU, 2 GB RAM) handles both running the app and building images, but **not simultaneously under heavy load**. During a deploy, Kamal builds the image first, then deploys it, so there's no overlap between building and the two-container swap. This works fine for this tutorial's small Rails app.

For larger apps with heavier builds, consider either:
- Upgrading to `e2-medium` (1 vCPU, 4 GB RAM) in `terraform-gcloud/main.tf`
- Using a dedicated builder instance (see below)

### Docker Build Cache on the Remote

The remote instance retains Docker's build cache between deploys. This means incremental builds (where only your Ruby code changed) are fast because cached layers for the base image, system packages, and gems are reused.

If you tear down and recreate the infrastructure, the build cache is lost and the first build will be a full rebuild.

### Using a Dedicated Builder Instance

For production use with a larger app, you may want a separate instance dedicated to building. This avoids any resource contention with the running app. You would:

1. Add a second `google_compute_instance` resource in `terraform-gcloud/main.tf` with Docker installed
2. Point `builder.remote` to that instance's IP
3. The builder instance can be a preemptible/spot instance to save costs (builds are short-lived)

For this tutorial, using the app server as the builder keeps things simple.

## Reverting to Local Builds

To go back to building locally (e.g., on a Linux x86_64 machine where QEMU isn't needed):

1. Comment out the `remote` line in `config/deploy.yml`:
   ```yaml
   builder:
     arch: amd64
     # remote: ssh://justin@34.29.79.152
   ```

2. Deploy as usual — Kamal will build locally.

## Troubleshooting

### "Cannot connect to the Docker daemon"

Ensure your SSH user is in the `docker` group on the remote instance:
```bash
ssh justin@<SERVER_IP> "groups"
# Should include: docker
```

If not, add it:
```bash
ssh justin@<SERVER_IP> "sudo usermod -aG docker justin"
```

Then disconnect and reconnect (group changes require a new session).

### "Permission denied (publickey)"

Ensure your SSH key is configured. The Terraform setup injects `~/.ssh/id_rsa.pub` into the instance metadata. If you've regenerated your SSH key since provisioning, run `terraform apply` again to update it.

### Build is slow on the remote

Check if Docker's build cache was cleared (e.g., after a `docker system prune` or infrastructure teardown). The first build after cache loss will be a full rebuild. Subsequent builds will be fast.

Also verify the instance isn't resource-constrained:
```bash
ssh justin@<SERVER_IP> "free -h && df -h /"
```
