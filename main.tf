# Configure the Google provider
provider "google" {
  credentials = file("google.json")
  project     = "<project-id>"
  region      = "us-central1"
}

# Create a Cloud Run service
resource "google_run_service" "docs-sync" {
  name       = "docs-sync"
  location   = "us-central1"
  platform   = "managed"
  metadata = {
    namespace = "<namespace>"
  }

  template {
    spec {
      container {
        image = "docs-sync"
      }
    }
  }
}

# Create a Cloud Scheduler job to run the Cloud Run service
resource "google_scheduler_job" "docs-sync" {
  name         = "docs-sync-job"
  description  = "Run the docs-sync Cloud Run service every week"
  schedule     = "0 0 * * 0" # At 00:00 on Sunday
  time_zone    = "America/New_York"
  http_target {
    http_method = "POST"
    uri         = "${google_run_service.docs-sync.status[0].url}"
  }
}
