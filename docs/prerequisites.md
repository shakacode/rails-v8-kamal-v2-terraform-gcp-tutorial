# Prerequisites

## GCP Account

You need a Google Cloud Platform (GCP) account to deploy this application. If you don't have one:

1. Go to [Google Cloud Console](https://console.cloud.google.com/) and sign up for an account. Google offers a [free trial](https://cloud.google.com/free) with $300 in credits.
2. Create a new project for this tutorial (e.g., `kamal-demo`). See [Understanding GCP Projects](#understanding-gcp-projects) below for details.
3. Enable billing for the project.
4. Install the [Google Cloud CLI (gcloud)](https://cloud.google.com/sdk/docs/install):
   - **macOS**: `brew install --cask google-cloud-sdk` (via [Homebrew](https://brew.sh/)) or download the [macOS installer](https://cloud.google.com/sdk/docs/install#mac)
   - **Linux**: See the [Linux installation guide](https://cloud.google.com/sdk/docs/install#linux)
   - **Windows**: Download the [Windows installer](https://cloud.google.com/sdk/docs/install#windows)
5. Authenticate with `gcloud`. See [Authenticating with gcloud](#authenticating-with-gcloud) below.
6. Enable the required APIs:
   ```bash
   gcloud services enable compute.googleapis.com sqladmin.googleapis.com secretmanager.googleapis.com
   ```

## Understanding GCP Projects

Everything in Google Cloud lives inside a **project**. A project is the top-level container for all your GCP resources (VMs, databases, secrets, etc.) and is also the unit for billing and access control. Think of it like a namespace that keeps your tutorial resources separate from anything else in your GCP account.

**Project Name vs. Project ID:**
- **Project Name**: A human-friendly label you choose when creating the project (e.g., `Kamal Demo`). This can be changed later and doesn't need to be unique.
- **Project ID**: A globally unique, immutable identifier (e.g., `kamal-demo-444506`). GCP may append random numbers to ensure uniqueness. This is what you use in CLI commands, Terraform configs, and API calls.

You can find your Project ID in the [Google Cloud Console](https://console.cloud.google.com/) — it's shown in the project selector dropdown at the top of the page, or on the project's Dashboard.

**For this tutorial**, you'll need to set the Project ID in `terraform-gcloud/variables.tf`:
```terraform
variable "project_id" {
  default = "kamal-demo-444506" # Replace with YOUR Project ID
}
```

## Authenticating with gcloud

The `gcloud` CLI requires authentication to interact with your GCP account. There are two types of login you'll need:

1. **`gcloud auth login`** — Authenticates **you** (your Google account) for running `gcloud` commands interactively. This opens a browser window where you sign in with your Google account.
   ```bash
   gcloud auth login
   ```
   After login, you'll see output like:
   ```
   You are now logged in as [you@example.com].
   Your current project is [kamal-demo-444506].
   ```

2. **`gcloud auth application-default login`** — Sets up **Application Default Credentials (ADC)** that tools like Terraform use to authenticate with GCP APIs. This is a separate credential from your interactive login.
   ```bash
   gcloud auth application-default login
   ```
   Terraform's Google provider automatically uses these credentials, so you don't need to manage service account key files for local development.

**Set your default project** so you don't have to pass `--project` with every command:
```bash
gcloud config set project YOUR_PROJECT_ID
```

**Verify your setup:**
```bash
gcloud config list
```
This shows your active account and project. You should see your email and project ID in the output.

**Useful commands:**
```bash
gcloud auth list                    # See which accounts are authenticated
gcloud config get-value project     # Check your current default project
gcloud projects list                # List all projects you have access to
```

## SSH Access for GCP

To set up SSH with Google Cloud Platform (GCP) for use with Terraform, follow these steps:

1. **Generate SSH Keys**:
   If you don't already have an SSH key pair, generate one using the following command:
   ```bash
   ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa
   ```

2. **Add SSH Key to GCP**:
   Add your public SSH key to your GCP project metadata. This allows you to SSH into instances created by Terraform.
   ```bash
   gcloud compute project-info add-metadata --metadata ssh-keys="$(whoami):$(cat ~/.ssh/id_rsa.pub)"
   ```

3. **Configure Terraform**:
   Ensure your `variables.tf` file includes the `ssh_user` variable:
   ```terraform
   variable "ssh_user" {
     description = "The SSH username to access the instance"
     type        = string
     default     = "your-username" # Replace with your SSH username
   }
   ```

4. **Reference SSH Key in Terraform**:
   In your `main.tf` file, configure the `google_compute_instance` resource to use the SSH key (in source code):
   ```terraform
   resource "google_compute_instance" "rails_app" {
     metadata = {
       ssh-keys = "${var.ssh_user}:${file("~/.ssh/id_rsa.pub")}"
     }
   }
   ```

5. **SSH into the Instance**:
   Once the instance is created, you can SSH into it using:
   ```bash
   gcloud compute ssh your-username@instance-name --zone=us-central1-a
   ```

Replace `your-username` and `instance-name` with your actual SSH username and instance name.

Or you can use the `ssh` command directly:
   ```bash
   ssh your-username@instance-ip
   ```
The instance-ip can be found in the `config/deploy.yml` which is updated after the Terraform setup done via `terraform-gcloud/bin/stand-up`.
