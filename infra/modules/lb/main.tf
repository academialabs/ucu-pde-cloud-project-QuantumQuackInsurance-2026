# Load balancer HTTP externo delante de Cloud Run.
# Solo se crea si enable_lb = true (el día de la demo). La forwarding rule
# cobra por hora, así que se destruye apenas termina la presentación.

variable "enable_lb" {
  description = "Crear el load balancer. false por defecto para no pagar."
  type        = bool
  default     = false
}

variable "name" {
  description = "Prefijo de los recursos del LB."
  type        = string
}

variable "region" {
  description = "Región del servicio de Cloud Run."
  type        = string
}

variable "cloud_run_service" {
  description = "Nombre del servicio de Cloud Run."
  type        = string
}

variable "labels" {
  description = "Etiquetas obligatorias."
  type        = map(string)
}

resource "google_compute_region_network_endpoint_group" "neg" {
  count                 = var.enable_lb ? 1 : 0
  name                  = "${var.name}-neg"
  region                = var.region
  network_endpoint_type = "SERVERLESS"
  cloud_run {
    service = var.cloud_run_service
  }
}

resource "google_compute_backend_service" "this" {
  count                 = var.enable_lb ? 1 : 0
  name                  = "${var.name}-backend"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  protocol              = "HTTP"
  backend {
    group = google_compute_region_network_endpoint_group.neg[0].id
  }
}

resource "google_compute_url_map" "this" {
  count           = var.enable_lb ? 1 : 0
  name            = "${var.name}-urlmap"
  default_service = google_compute_backend_service.this[0].id
}

resource "google_compute_target_http_proxy" "this" {
  count   = var.enable_lb ? 1 : 0
  name    = "${var.name}-proxy"
  url_map = google_compute_url_map.this[0].id
}

resource "google_compute_global_forwarding_rule" "this" {
  count                 = var.enable_lb ? 1 : 0
  name                  = "${var.name}-fr"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  target                = google_compute_target_http_proxy.this[0].id
  port_range            = "80"
  labels                = var.labels
}

output "ip" {
  value = var.enable_lb ? google_compute_global_forwarding_rule.this[0].ip_address : null
}
