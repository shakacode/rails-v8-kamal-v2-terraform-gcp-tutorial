# Prerequisites

## GCP Account


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
