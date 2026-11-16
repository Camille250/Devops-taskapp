output "cluster_name" {
  value = kind_cluster.this.name
}

output "ports" {
  description = "Open these ports (Codespaces: the PORTS tab, or run `make urls`)"
  value       = { for name, p in var.ports : name => p.host_port }
}
