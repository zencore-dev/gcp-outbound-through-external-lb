terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~>4.53"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~>4.53"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}
