# Prerequisites

## GCP Account

You need a Google Cloud Platform (GCP) account to deploy this application. If you don't have one:

1. Go to [Google Cloud Console](https://console.cloud.google.com/) and sign up for an account. Google offers a [free trial](https://cloud.google.com/free) with $300 in credits.
2. Create a new project for this tutorial (e.g., `kamal-demo`).
3. Enable billing for the project.
4. Install the [Google Cloud CLI (gcloud)](https://cloud.google.com/sdk/docs/install):
   - **macOS**: `brew install --cask google-cloud-sdk` (via [Homebrew](https://brew.sh/)) or download the [macOS installer](https://cloud.google.com/sdk/docs/install#mac)
   - **Linux**: See the [Linux installation guide](https://cloud.google.com/sdk/docs/install#linux)
   - **Windows**: Download the [Windows installer](https://cloud.google.com/sdk/docs/install#windows)

   After installation, authenticate and set your project:
   ```bash
   gcloud auth login
   gcloud config set project YOUR_PROJECT_ID
   ```
5. Enable the required APIs:
   ```bash
   gcloud services enable compute.googleapis.com sqladmin.googleapis.com secretmanager.googleapis.com
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
