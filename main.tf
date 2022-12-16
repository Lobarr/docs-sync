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

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.45.0"
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
    "serviceusage.googleapis.com",
    "run.googleapis.com",
    "cloudscheduler.googleapis.com",
    "containerregistry.googleapis.com",
  ])
  project = var.project_id
  service = each.key
}

# Create a Cloud Run service
resource "google_cloud_run_service" "docs_sync_service" {
  name     = "docs-sync-service"
  location = var.location

  template {
    spec {
      containers {
        image = "ghcr.io/lobarr/docs-sync:latest"
      }
      service_account_name = var.service_account
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  depends_on = [
    google_project_service.services
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
    uri         = google_cloud_run_service.docs_sync_service.status[0].url
  }
  depends_on = [
    # google_project_service.cloud_scheduler,
    google_cloud_run_service.docs_sync_service
  ]
}

# Display useful context from dpeloyments 
output "cloud_run_service_url" {
  value = google_cloud_run_service.docs_sync_service.status[0].url
}
