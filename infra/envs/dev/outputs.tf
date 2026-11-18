output "app_url" {
  description = "URL pública del portal."
  value       = module.app.url
}

output "bucket_name" {
  value = module.bucket.name
}

output "registry_url" {
  value = module.registry.repository_url
}

output "lb_ip" {
  description = "IP del load balancer (solo si enable_lb = true)."
  value       = module.lb.ip
}
