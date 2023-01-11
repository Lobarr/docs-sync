variable "project_id" {
  type      = string
  sensitive = true
}

variable "location" {
  type      = string
  sensitive = true
}

variable "service_account" {
  type      = string
  sensitive = true
}

variable "docs_sync_image" {
  type      = string
  sensitive = true
}

variable "credentials_0_email" {
  type      = string
  sensitive = true
}

variable "credentials_0_password" {
  type      = string
  sensitive = true
}

variable "credentials_0_imap_server" {
  type      = string
  sensitive = true
}

variable "mails_from_0" {
  type      = string
  sensitive = true
}

variable "persist_to_firestore" {
  type      = string
  sensitive = true
}

variable "upload_to_drive" {
  type      = string
  sensitive = true
}

variable "drive_api_token" {
  type      = string
  sensitive = true
}

variable "folder_id" {
  type      = string
  sensitive = true
}

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.47.0"
    }
  }
  backend "gcs" {
    bucket = "docs-sync-tfstate"
    prefix = "tf/state"
  }
}

# Configure the Google provider
provider "google" {
  project = var.project_id
  region  = var.location
}

# Enable required cloud services
resource "google_project_service" "services" {
  for_each = toset([
    "cloudscheduler.googleapis.com",
    "containerregistry.googleapis.com",
    "drive.googleapis.com",
    "firestore.googleapis.com",
    "run.googleapis.com",
    "serviceusage.googleapis.com",
  ])
  project = var.project_id
  service = each.key
}

# Create a Cloud Firestore instance
resource "google_filestore_instance" "docs_sync" {
  name     = "docs-sync"
  location = var.location
  tier     = "STANDARD"

  file_shares {
    capacity_gb = 1024
    name        = "share1"
  }

  networks {
    network = "default"
    modes   = ["MODE_IPV4"]
  }
}

resource "google_secret_manager_secret" "docs_sync_config" {
  secret_id = "docs_sync_config"

  replication {
    user_managed {
      replicas {
        location = var.location
      }
    }
  }
}

resource "google_secret_manager_secret_version" "docs_sync_config_version" {
  secret      = google_secret_manager_secret.docs_sync_config.id
  secret_data = <<EOT
  # process emails sent to the following emails
  credentials:
    - email: ${var.credentials_0_email}
      password: ${var.credentials_0_password}
      imap_server: ${var.credentials_0_imap_server}
      imap_port: 993
  # process email sent from the following emails
  mails_from:
    - ${var.mails_from_0}
  folder_id: ${var.folder_id}
  # flag that determines whether syncher uploads attachments to google drive
  upload_to_drive: ${var.upload_to_drive}
  # flag that determines whether syncer progress is persisted to firestore
  persist_to_firestore: ${var.persist_to_firestore}
  # number of emails to process per credential
  emails_processed_limit: -1
  # wires up the invokation of the sync operation to an http server
  enable_http_server: true
  # API token used to authenticate to google drive
  drive_api_token: some-api-token
  EOT
}

# Create a Cloud Run service
resource "google_cloud_run_v2_service" "docs_sync" {
  name     = "docs-sync"
  location = var.location
  ingress  = "INGRESS_TRAFFIC_INTERNAL_ONLY"

  template {
    scaling {
      max_instance_count = 1
    }
    containers {
      image = var.docs_sync_image
    }
    volumes {
      name = "docs-sync-config"
      secret {
        secret       = google_secret_manager_secret.docs_sync_config.secret_id
        default_mode = 0444
        items {
          version = "latest"
          path    = "configs/config.yaml"
          mode    = 0400
        }
      }
    }
    service_account = var.service_account
  }

  traffic {
    percent = 100
  }

  depends_on = [
    google_project_service.services,
    google_filestore_instance.docs_sync,
  ]
}

# Create serivce account used by cloud run service
resource "google_service_account" "docs_sync_sa" {
  project     = var.project_id
  account_id  = "docs-sync-sa"
  description = "sa used to give cloud run service all permissions they need"
}

# Grant cloud firestore and cloud scheduler permission to write to the docs-sync service 
resource "google_cloud_run_service_iam_member" "required_access" {
  for_each = toset(["roles/run.invoker", "roles/datastore.user"])
  project  = var.project_id
  location = var.location
  service  = google_cloud_run_v2_service.docs_sync.name
  role     = each.key
  member   = "serviceAccount:${google_service_account.docs_sync_sa.email}"
  depends_on = [
    google_cloud_run_v2_service.docs_sync,
    google_service_account.docs_sync_sa
  ]
}

resource "google_secret_manager_secret_iam_member" "docs_sync_config_access" {
  secret_id = google_secret_manager_secret.docs_sync_config.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.docs_sync_sa.email}"
}

# Create a Cloud Scheduler job to run the Cloud Run service
resource "google_cloud_scheduler_job" "docs_sync_job" {
  name        = "docs-sync-job"
  description = "Run the docs-sync Cloud Run service every week"
  schedule    = "0 0 * * 0" # At 00:00 on Sunday
  time_zone   = "America/New_York"
  http_target {
    http_method = "POST"
    uri         = "${google_cloud_run_v2_service.docs_sync.uri}/sync"
  }
  depends_on = [
    google_cloud_run_v2_service.docs_sync,
    google_service_account.docs_sync_sa,
    google_cloud_run_service_iam_member.required_access
  ]
}

# Display useful context from dpeloyments 
output "cloud_run_service_url" {
  value = google_cloud_run_v2_service.docs_sync.uri
}
