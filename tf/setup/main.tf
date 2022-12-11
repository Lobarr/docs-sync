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
    random = {
      source  = "hashicorp/random"
      version = "3.4.3"
    }
  }
}

# Configure the Google provider
provider "google" {
  project      = var.project_id
  region       = var.location
  access_token = var.access_token
}


resource "random_id" "bucket_suffix" {
  byte_length = 8
}

resource "google_storage_bucket" "doc_sync_tfstate" {
  name          = "docs-sync-tfstate-${random_id.bucket_suffix.hex}"
  force_destroy = false
  location      = "US"
  storage_class = "STANDARD"
  versioning {
    enabled = true
  }
}

output "bucket_name" {
  value = google_storage_bucket.doc_sync_tfstate
}

output "bucket_suffix" {
  value = random_id.bucket_suffix
}
