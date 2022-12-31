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
  sensitive = false
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

variable "mails_from" {
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

resource "google_secret_manager_secret" "credentials_0_email" {
  secret_id = "credentials_0_email"

  replication {
    user_managed {
      replicas {
        location = var.location
      }
    }
  }
}

resource "google_secret_manager_secret_version" "credentials_0_email_version" {
  secret      = google_secret_manager_secret.credentials_0_email.id
  secret_data = var.credentials_0_email
}

resource "google_secret_manager_secret" "credentials_0_password" {
  secret_id = "credentials_0_password"

  replication {
    user_managed {
      replicas {
        location = var.location
      }
    }
  }
}

resource "google_secret_manager_secret_version" "credentials_0_password_version" {
  secret      = google_secret_manager_secret.credentials_0_password.id
  secret_data = var.credentials_0_password
}

resource "google_secret_manager_secret" "credentials_0_imap_server" {
  secret_id = "credentials_0_imap_server"

  # labels = {
  #   mails_from                = var.mails_from
  #   persist_to_firestore      = var.persist_to_firestore
  #   upload_to_drive           = var.upload_to_drive
  #   drive_api_token           = var.drive_api_token
  #   folder_id                 = var.folder_id
  # }

  replication {
    user_managed {
      replicas {
        location = var.location
      }
    }
  }
}

resource "google_secret_manager_secret_version" "credentials_0_imap_server_version" {
  secret      = google_secret_manager_secret.credentials_0_imap_server.id
  secret_data = var.credentials_0_imap_server
}

resource "google_secret_manager_secret" "mails_from" {
  secret_id = "mails_from"


  replication {
    user_managed {
      replicas {
        location = var.location
      }
    }
  }
}

resource "google_secret_manager_secret_version" "mails_from_version" {
  secret      = google_secret_manager_secret.mails_from.id
  secret_data = var.mails_from
}

resource "google_secret_manager_secret" "persist_to_firestore" {
  secret_id = "persist_to_firestore"


  replication {
    user_managed {
      replicas {
        location = var.location
      }
    }
  }
}

resource "google_secret_manager_secret_version" "persist_to_firestore_version" {
  secret      = google_secret_manager_secret.persist_to_firestore.id
  secret_data = var.persist_to_firestore
}

resource "google_secret_manager_secret" "upload_to_drive" {
  secret_id = "upload_to_drive"

  replication {
    user_managed {
      replicas {
        location = var.location
      }
    }
  }
}

resource "google_secret_manager_secret_version" "upload_to_drive_version" {
  secret      = google_secret_manager_secret.upload_to_drive.id
  secret_data = var.upload_to_drive
}

resource "google_secret_manager_secret" "drive_api_token" {
  secret_id = "drive_api_token"

  replication {
    user_managed {
      replicas {
        location = var.location
      }
    }
  }
}

resource "google_secret_manager_secret_version" "drive_api_token_version" {
  secret      = google_secret_manager_secret.drive_api_token.id
  secret_data = var.drive_api_token
}

resource "google_secret_manager_secret" "folder_id" {
  secret_id = "folder_id"

  replication {
    user_managed {
      replicas {
        location = var.location
      }
    }
  }
}

resource "google_secret_manager_secret_version" "folder_Id_version" {
  secret      = google_secret_manager_secret.folder_id.id
  secret_data = var.folder_id
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
      env {
        name = "CREDENTIALS_0_EMAIL"
        value_source {
          secret_key_ref {
            secret = google_secret_manager_secret.credentials_0_email.id
          }
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

//TODO: figure out how to give cluod run secretAccessor
resource "google_secret_manager_secret_iam_member" "secret-access" {
  for_each  = toset([google_secret_manager_secret.credentials_0_email.id])
  secret_id = each.key
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.project_id}-compute@developer.gserviceaccount.com"
}

# Create serivce account for cloud scheduler to be able to invoke the cloud run service
resource "google_service_account" "cloud_scheduler_invoker" {
  project     = var.project_id
  account_id  = "cloud-run-scheduler-invoker"
  description = "cloud scheduler service account used to invoke cloud run services"
}

# Grant cloud scheduler permission to invoke the docs-sync service
resource "google_cloud_run_service_iam_member" "scheduler_invoke_docs_sync" {
  project  = var.project_id
  location = var.location
  service  = google_cloud_run_v2_service.docs_sync.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.cloud_scheduler_invoker.email}"
  depends_on = [
    google_cloud_run_v2_service.docs_sync,
    google_service_account.cloud_scheduler_invoker
  ]
}

# Create serivce account for cloud run to be able to write to firestore 
resource "google_service_account" "cloud_firestore_invoker" {
  project     = var.project_id
  account_id  = "cloud-firestore-run-invoker"
  description = "cloud run service account used to write to firestore"
}

# Grant cloud firestore permission to write to the docs-sync instance 
resource "google_cloud_run_service_iam_member" "run_write_docs_sync" {
  project  = var.project_id
  location = var.location
  service  = google_cloud_run_v2_service.docs_sync.name
  role     = "roles/datastore.user"
  member   = "serviceAccount:${google_service_account.cloud_firestore_invoker.email}"
  depends_on = [
    google_cloud_run_v2_service.docs_sync,
    google_service_account.cloud_firestore_invoker
  ]
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
    google_service_account.cloud_scheduler_invoker,
    google_cloud_run_service_iam_member.scheduler_invoke_docs_sync
  ]
}

# Display useful context from dpeloyments 
output "cloud_run_service_url" {
  value = google_cloud_run_v2_service.docs_sync.uri
}
