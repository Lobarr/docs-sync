variable "project_id" {
  type = string
}

variable "location" {
  type = string
}

variable "access_token" {
  type = string
}

variable "billing_account" {
  type = string
}

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.45.0"
    }
  }
}

# Configure the Google provider
provider "google" {
  project      = var.project_id
  region       = var.location
  access_token = var.access_token
}
# Create a project
resource "google_project" "doc_sync_project" {
  name            = "Doc Sync Project"
  project_id      = "doc-sync"
  billing_account = var.billing_account
}

# Create service account
resource "google_service_account" "docs_sync_service_account" {
  account_id   = "service-account-id"
  display_name = "Service Account"
}

# Enable cloud run service
resource "google_project_service" "cloud_run" {
  project                    = var.project_id
  service                    = "run.googleapis.com"
  disable_dependent_services = true
  depends_on = [
    google_project.doc_sync_project,
    google_service_account.docs_sync_service_account
  ]
}

# Create a Cloud Run service
resource "google_cloud_run_service" "docs_sync_service" {
  name     = "docs-sync-service"
  location = var.location

  template {
    spec {
      containers {
        image = "ghcr.io/lobarr/docs-sync"
      }
      service_account_name = google_service_account.docs_sync_service_account.email
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  depends_on = [google_project_service.cloud_run]
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
    google_cloud_run_service.docs_sync_service
  ]
}

# Display useful context from dpeloyments 
output "project_number" {
  value = google_project.doc_sync_project.number
}

output "serivce_account" {
  value = google_service_account.docs_sync_service_account.id
}

output "cloud_run_service_url" {
  value = google_cloud_run_service.docs_sync_service.status[0].url
}
