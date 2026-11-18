# Bootstrap: lo ÚNICO que se aplica a mano, una sola vez, desde la máquina de un integrante.
# Crea: APIs, bucket del state remoto, Workload Identity Federation (GitHub → GCP)
# y la service account de CI. Todo lo demás lo despliega GitHub Actions.

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
  # La API de presupuestos necesita un proyecto de cuota con credenciales de usuario.
  user_project_override = true
  billing_project       = var.project_id
}

variable "project_id" {
  description = "ID del proyecto de GCP."
  type        = string
}

variable "region" {
  description = "Región. us-central1 para quedar dentro del free tier de Cloud Storage."
  type        = string
  default     = "us-central1"
}

variable "github_repo" {
  description = "Repo del equipo en formato owner/nombre. Solo ese repo puede autenticarse."
  type        = string
  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repo))
    error_message = "Tiene que tener el formato owner/repo."
  }
}

variable "billing_account" {
  description = "ID de la cuenta de facturación (XXXXXX-XXXXXX-XXXXXX)."
  type        = string
}

variable "alert_emails" {
  description = "Mails de los 3 integrantes para el presupuesto."
  type        = list(string)
}

variable "budget_usd" {
  description = "Presupuesto mensual en USD, medido antes de créditos."
  type        = number
  default     = 5
}

locals {
  labels = {
    project = "quantumquack"
    team    = "ucu-cloud"
    env     = "bootstrap"
    owner   = "equipo-quantumquack"
  }
  apis = [
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "storage.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "compute.googleapis.com",
    "billingbudgets.googleapis.com",
  ]
}

resource "google_project_service" "apis" {
  for_each           = toset(local.apis)
  service            = each.value
  disable_on_destroy = false
}

# --- State remoto ---
resource "google_storage_bucket" "tfstate" {
  name                        = "${var.project_id}-tfstate"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false
  labels                      = local.labels

  versioning {
    enabled = true
  }

  # Solo guardamos las últimas 5 versiones del state (para no acumular).
  lifecycle_rule {
    condition {
      num_newer_versions = 5
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }
}

data "google_project" "current" {}

# --- Presupuesto: alertas al 50/80/100 % a los 3 integrantes ---
resource "google_monitoring_notification_channel" "budget" {
  for_each     = toset(var.alert_emails)
  display_name = "Presupuesto ${each.value}"
  type         = "email"
  labels = {
    email_address = each.value
  }
  depends_on = [google_project_service.apis]
}

resource "google_billing_budget" "this" {
  billing_account = var.billing_account
  display_name    = "quantumquack - presupuesto mensual"

  budget_filter {
    projects = ["projects/${data.google_project.current.number}"]
    # Gasto ANTES de créditos: avisa si algo sale del free tier
    # aunque el crédito de prueba lo esté cubriendo.
    credit_types_treatment = "EXCLUDE_ALL_CREDITS"
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.budget_usd)
    }
  }

  dynamic "threshold_rules" {
    for_each = [0.5, 0.8, 1.0]
    content {
      threshold_percent = threshold_rules.value
    }
  }

  all_updates_rule {
    monitoring_notification_channels = [for c in google_monitoring_notification_channel.budget : c.id]
    disable_default_iam_recipients   = false
  }

  depends_on = [google_project_service.apis]
}

# --- Workload Identity Federation: GitHub Actions sin claves JSON ---
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-pool"
  display_name              = "GitHub Actions"
  depends_on                = [google_project_service.apis]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }
  # Solo tokens que vengan de NUESTRO repo.
  attribute_condition = "assertion.repository == \"${var.github_repo}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "ci" {
  account_id   = "sa-ci-github"
  display_name = "CI GitHub Actions (Terraform + deploy)"
}

resource "google_service_account_iam_member" "ci_wif" {
  service_account_id = google_service_account.ci.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
}

# Roles predefinidos acotados a lo que Terraform administra. Sin owner/editor.
resource "google_project_iam_member" "ci_roles" {
  for_each = toset([
    "roles/run.admin",
    "roles/artifactregistry.admin",
    "roles/storage.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/monitoring.editor",
    "roles/logging.configWriter",
    "roles/compute.loadBalancerAdmin",
    "roles/serviceusage.serviceUsageConsumer",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.ci.email}"
}

output "tfstate_bucket" {
  value = google_storage_bucket.tfstate.name
}

output "wif_provider" {
  description = "Va como secret GCP_WIF_PROVIDER en GitHub."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "ci_service_account" {
  description = "Va como secret GCP_CI_SA en GitHub."
  value       = google_service_account.ci.email
}
