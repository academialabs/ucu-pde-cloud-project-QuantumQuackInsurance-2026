terraform {
  required_version = ">= 1.9.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_project" "current" {}

locals {
  name = "quantumquack-${var.env}"
  # Etiquetas obligatorias en todos los recursos.
  labels = {
    project = "quantumquack"
    team    = "ucu-cloud"
    env     = var.env
    owner   = var.owner
  }
}

module "registry" {
  source = "../../modules/registry"
  region = var.region
  labels = local.labels
}

module "bucket" {
  source = "../../modules/bucket"
  name   = "${var.project_id}-${local.name}-claims"
  region = var.region
  labels = local.labels
}

module "app" {
  source      = "../../modules/container_service"
  name        = local.name
  region      = var.region
  image       = var.image
  bucket_name = module.bucket.name
  labels      = local.labels
}

module "lb" {
  source            = "../../modules/lb"
  enable_lb         = var.enable_lb
  name              = local.name
  region            = var.region
  cloud_run_service = module.app.service_name
  labels            = local.labels
}

module "monitoring" {
  source         = "../../modules/monitoring"
  name           = local.name
  service_name   = module.app.service_name
  bucket_name    = module.bucket.name
  alert_emails   = var.alert_emails
  project_number = data.google_project.current.number
}
