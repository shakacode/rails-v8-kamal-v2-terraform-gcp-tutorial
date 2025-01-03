terraform {
  backend "local" {
    path = "./terraform-state/terraform.tfstate"
  }
}

########################################
#   Provider Configuration
########################################
provider "google" {
  project = var.project_id
  region  = "us-central1"
  zone    = "us-central1-a"
}

########################################
#   Service Account + IAM Bindings
########################################
resource "google_service_account" "rails_app_service_account" {
  account_id   = "rails-app-service-account"
  display_name = "Service Account for Rails App Instance"
}

# Grant Required IAM Roles to the Service Account
resource "google_project_iam_member" "sql_client_role" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.rails_app_service_account.email}"
}

resource "google_project_iam_member" "iam_service_account_user_role" {
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.rails_app_service_account.email}"
}

########################################
#   Compute Instance (runs Cloud SQL Proxy)
########################################
resource "google_compute_instance" "rails_app" {
  name         = "rails-app-instance"
  machine_type = "e2-micro" # Minimal compute resources
  zone         = "us-central1-a"
  tags         = ["http-server", "https-server"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    network = "default"

    access_config {
      # This is required to assign an external IP
    }
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${file("~/.ssh/id_rsa.pub")}"
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    set -e

    # Update and install required packages
    apt-get update
    apt-get install -y docker.io lsof

    # Add user to Docker group
    usermod -aG docker ${var.ssh_user}
    systemctl enable docker
    systemctl start docker

    # Download and set up the Cloud SQL Proxy
    wget -q https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.8.0/cloud-sql-proxy.linux.amd64 -O /usr/local/bin/cloud_sql_proxy
    chmod +x /usr/local/bin/cloud_sql_proxy

    # Stop any conflicting processes on port 5432
    fuser -k 5432/tcp || true

    # Create and configure the Cloud SQL Proxy systemd service
    cat <<EOF > /etc/systemd/system/cloud-sql-proxy.service
    [Unit]
    Description=Google Cloud SQL Proxy
    After=network.target

    [Service]
    Type=simple
    ExecStart=/usr/local/bin/cloud_sql_proxy ${google_sql_database_instance.rails_db_instance.connection_name} --address=0.0.0.0 --port=5432
    Restart=always
    RestartSec=5
    StandardOutput=journal
    StandardError=journal

    [Install]
    WantedBy=multi-user.target
    EOF

    # Ensure permissions and start the service
    systemctl daemon-reload
    systemctl enable cloud-sql-proxy
    systemctl start cloud-sql-proxy

    # Verify the service status
    systemctl status cloud-sql-proxy || true
  EOT

  service_account {
    email = google_service_account.rails_app_service_account.email
    scopes = [
      "https://www.googleapis.com/auth/sqlservice.admin",
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}

########################################
#   Cloud SQL Instance + Databases
########################################
resource "google_sql_database_instance" "rails_db_instance" {
  name                 = "rails-db-instance"
  database_version     = "POSTGRES_16"
  region               = "us-central1"
  deletion_protection  = false

  settings {
    tier              = "db-f1-micro" # Smallest tier for cost-effectiveness
    edition           = "ENTERPRISE"
    availability_type = "ZONAL" # Single-zone for reduced cost
    disk_autoresize = false # Avoid unnecessary storage scaling
    backup_configuration {
      enabled                        = false # Disable automatic backups to reduce costs
      point_in_time_recovery_enabled = false # Disable PITR for experimentation
    }
  }
}

########################################
#   Database User
########################################
resource "google_sql_user" "rails_db_user" {
  name     = "rails_user"
  password = "supersecurepassword"
  instance = google_sql_database_instance.rails_db_instance.name
}

# Primary Database
resource "google_sql_database" "rails_database_primary" {
  name     = "rails_kamal_demo_production"
  instance = google_sql_database_instance.rails_db_instance.name
  depends_on = [google_sql_user.rails_db_user]
}

# Cache Database
resource "google_sql_database" "rails_database_cache" {
  name     = "rails_kamal_demo_production_cache"
  instance = google_sql_database_instance.rails_db_instance.name
  depends_on = [google_sql_user.rails_db_user]
}

# Queue Database
resource "google_sql_database" "rails_database_queue" {
  name     = "rails_kamal_demo_production_queue"
  instance = google_sql_database_instance.rails_db_instance.name
  depends_on = [google_sql_user.rails_db_user]
}

# Cable Database
resource "google_sql_database" "rails_database_cable" {
  name     = "rails_kamal_demo_production_cable"
  instance = google_sql_database_instance.rails_db_instance.name
  depends_on = [google_sql_user.rails_db_user]
}

########################################
#   Firewall rule to allow HTTP/HTTPS traffic
########################################
resource "google_compute_firewall" "default" {
  name    = "allow-http-https"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  # Allow traffic from all IPs
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server", "https-server"]
}
