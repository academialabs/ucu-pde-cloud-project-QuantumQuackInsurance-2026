variable "name" {
  description = "Nombre global del bucket."
  type        = string
}

variable "region" {
  description = "Región. us-central1 entra en el free tier."
  type        = string
}

variable "cors_origins" {
  description = "Orígenes que pueden hacer PUT desde el navegador."
  type        = list(string)
  default     = ["*"]
}

variable "test_data_ttl_days" {
  description = "Días hasta borrar datos de prueba (prefijo uploads/test-)."
  type        = number
  default     = 7
}

variable "labels" {
  description = "Etiquetas obligatorias."
  type        = map(string)
}

resource "google_storage_bucket" "this" {
  name                        = var.name
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true # para que destroy.yml no falle con fotos de prueba
  labels                      = var.labels
  # Cifrado: Google-managed keys (por defecto). CMEK cobra por clave en KMS.

  cors {
    origin          = var.cors_origins
    method          = ["PUT"]
    response_header = ["Content-Type", "x-goog-content-length-range"]
    max_age_seconds = 300
  }

  # Ciclo de vida pedido por la consigna.
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type          = "SetStorageClass"
      storage_class = "ARCHIVE"
    }
  }

  # TTL de datos de prueba.
  lifecycle_rule {
    condition {
      age            = var.test_data_ttl_days
      matches_prefix = ["uploads/test-", "uploads/sin-numero/"]
    }
    action {
      type = "Delete"
    }
  }
}

output "name" {
  value = google_storage_bucket.this.name
}
