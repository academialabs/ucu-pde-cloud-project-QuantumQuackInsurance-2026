variable "region" {
  description = "Región del repositorio."
  type        = string
}

variable "repository_id" {
  description = "Nombre del repositorio Docker."
  type        = string
  default     = "quantumquack"
}

variable "keep_versions" {
  description = "Cuántas imágenes conservar. Pocas para no pasar los 0,5 GB gratis."
  type        = number
  default     = 3
  validation {
    condition     = var.keep_versions >= 1 && var.keep_versions <= 10
    error_message = "Entre 1 y 10."
  }
}

variable "labels" {
  description = "Etiquetas obligatorias."
  type        = map(string)
}

resource "google_artifact_registry_repository" "this" {
  location      = var.region
  repository_id = var.repository_id
  format        = "DOCKER"
  description   = "Imágenes de QuantumQuack"
  labels        = var.labels

  cleanup_policy_dry_run = false

  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = var.keep_versions
    }
  }

  cleanup_policies {
    id     = "delete-old"
    action = "DELETE"
    condition {
      tag_state  = "ANY"
      older_than = "86400s"
    }
  }
}

output "repository_url" {
  value = "${var.region}-docker.pkg.dev/${google_artifact_registry_repository.this.project}/${google_artifact_registry_repository.this.repository_id}"
}
