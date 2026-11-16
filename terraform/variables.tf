variable "cluster_name" {
  description = "Name of the local kind cluster"
  type        = string
  default     = "devops-lab"
}

variable "kubernetes_version" {
  description = "kindest/node image tag, e.g. v1.34.11 (empty = provider default)"
  type        = string
  default     = ""
}

variable "ports" {
  description = "Host port -> NodePort for each UI. node_port values must match values/*.yaml"
  type = map(object({
    host_port = number
    node_port = number
  }))
  default = {
    taskapp      = { host_port = 8081, node_port = 30080 } # via Traefik ingress
    argocd       = { host_port = 8082, node_port = 30880 }
    grafana      = { host_port = 3000, node_port = 30300 }
    prometheus   = { host_port = 9090, node_port = 30090 }
    alertmanager = { host_port = 9093, node_port = 30903 }
  }
}

variable "grafana_root_url" {
  description = "Public Grafana URL (set automatically by `make infra` in Codespaces)"
  type        = string
  default     = ""
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "chart_versions" {
  description = "Pinned Helm chart versions"
  type        = map(string)
  default = {
    traefik    = "42.3.1"
    argocd     = "10.14.0"
    monitoring = "92.21.2"
  }
}
