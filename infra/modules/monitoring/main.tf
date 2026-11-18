variable "name" {
  description = "Prefijo de los recursos."
  type        = string
}

variable "service_name" {
  description = "Servicio de Cloud Run a monitorear."
  type        = string
}

variable "bucket_name" {
  description = "Bucket de fotos."
  type        = string
}

variable "alert_emails" {
  description = "Mails del equipo para las alertas."
  type        = list(string)
}

variable "project_number" {
  description = "Número del proyecto."
  type        = string
}

variable "log_retention_days" {
  description = "Retención del bucket de logs _Default."
  type        = number
  default     = 7
}

resource "google_monitoring_notification_channel" "email" {
  for_each     = toset(var.alert_emails)
  display_name = "Email ${each.value}"
  type         = "email"
  labels = {
    email_address = each.value
  }
}

# --- Alerta: cualquier 5xx en Cloud Run ---
resource "google_monitoring_alert_policy" "errors_5xx" {
  display_name          = "${var.name} - errores 5xx en Cloud Run"
  combiner              = "OR"
  notification_channels = [for c in google_monitoring_notification_channel.email : c.id]

  conditions {
    display_name = "5xx > 0 en 1 minuto"
    condition_threshold {
      filter          = "resource.type = \"cloud_run_revision\" AND resource.labels.service_name = \"${var.service_name}\" AND metric.type = \"run.googleapis.com/request_count\" AND metric.labels.response_code_class = \"5xx\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    content   = "Cloud Run devolvió errores 5xx. Revisar logs en Logging. Para la demo se dispara con GET /api/boom."
    mime_type = "text/markdown"
  }
}

# --- Dashboard ---
resource "google_monitoring_dashboard" "main" {
  dashboard_json = jsonencode({
    displayName = "QuantumQuack"
    mosaicLayout = {
      columns = 12
      tiles = [
        {
          width = 6, height = 4, xPos = 0, yPos = 0
          widget = {
            title = "Requests por código"
            xyChart = { dataSets = [{
              plotType = "STACKED_BAR"
              timeSeriesQuery = { timeSeriesFilter = {
                filter      = "resource.type=\"cloud_run_revision\" resource.labels.service_name=\"${var.service_name}\" metric.type=\"run.googleapis.com/request_count\""
                aggregation = { alignmentPeriod = "60s", perSeriesAligner = "ALIGN_SUM", crossSeriesReducer = "REDUCE_SUM", groupByFields = ["metric.labels.response_code_class"] }
              } }
            }] }
          }
        },
        {
          width = 6, height = 4, xPos = 6, yPos = 0
          widget = {
            title = "Latencia p95 (ms)"
            xyChart = { dataSets = [{
              plotType = "LINE"
              timeSeriesQuery = { timeSeriesFilter = {
                filter      = "resource.type=\"cloud_run_revision\" resource.labels.service_name=\"${var.service_name}\" metric.type=\"run.googleapis.com/request_latencies\""
                aggregation = { alignmentPeriod = "60s", perSeriesAligner = "ALIGN_PERCENTILE_95" }
              } }
            }] }
          }
        },
        {
          width = 6, height = 4, xPos = 0, yPos = 4
          widget = {
            title = "Objetos en el bucket"
            xyChart = { dataSets = [{
              plotType = "LINE"
              timeSeriesQuery = { timeSeriesFilter = {
                filter      = "resource.type=\"gcs_bucket\" resource.labels.bucket_name=\"${var.bucket_name}\" metric.type=\"storage.googleapis.com/storage/object_count\""
                aggregation = { alignmentPeriod = "300s", perSeriesAligner = "ALIGN_MEAN" }
              } }
            }] }
          }
        },
        {
          width = 6, height = 4, xPos = 6, yPos = 4
          widget = {
            title = "Bytes en el bucket"
            xyChart = { dataSets = [{
              plotType = "LINE"
              timeSeriesQuery = { timeSeriesFilter = {
                filter      = "resource.type=\"gcs_bucket\" resource.labels.bucket_name=\"${var.bucket_name}\" metric.type=\"storage.googleapis.com/storage/total_bytes\""
                aggregation = { alignmentPeriod = "300s", perSeriesAligner = "ALIGN_MEAN" }
              } }
            }] }
          }
        },
      ]
    }
  })
}

# --- Retención de logs a 7 días (por defecto son 30) ---
resource "google_logging_project_bucket_config" "default" {
  project        = "projects/${var.project_number}"
  location       = "global"
  bucket_id      = "_Default"
  retention_days = var.log_retention_days
}
