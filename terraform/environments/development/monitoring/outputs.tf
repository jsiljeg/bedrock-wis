output "grafana_url"    { value = "http://${var.host}:3000" }
output "prometheus_url" { value = "http://${var.host}:9090" }
output "alertmanager"   { value = "http://${var.host}:9093" }
