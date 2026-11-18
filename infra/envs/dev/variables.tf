variable "project_id" {
  description = "ID del proyecto de GCP."
  type        = string
}

variable "region" {
  description = "Región. us-central1 para quedar dentro del free tier."
  type        = string
  default     = "us-central1"
  validation {
    condition     = contains(["us-central1", "us-east1", "us-west1"], var.region)
    error_message = "Solo regiones con free tier de Cloud Storage: us-central1, us-east1 o us-west1."
  }
}

variable "env" {
  description = "Nombre del entorno."
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Responsable de los recursos (etiqueta owner)."
  type        = string
  default     = "equipo-quantumquack"
}

variable "image" {
  description = "Imagen del contenedor. La primera vez usa la imagen de ejemplo de Google."
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "enable_lb" {
  description = "Crear el load balancer. Solo el día de la demo: cobra por hora."
  type        = bool
  default     = false
}

variable "alert_emails" {
  description = "Mails del equipo para las alertas."
  type        = list(string)
  validation {
    condition     = length(var.alert_emails) > 0
    error_message = "Poné al menos un mail."
  }
}
