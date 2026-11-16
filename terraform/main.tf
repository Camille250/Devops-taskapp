# ---------------------------------------------------------------------------
# Infrastructure as Code: everything below is created by `terraform apply`
# and destroyed by `terraform destroy`.
#
#   kind cluster (Kubernetes in Docker)
#     ├── traefik               ingress controller -> TaskApp on port 8081
#     ├── argocd                GitOps continuous delivery
#     └── kube-prometheus-stack Prometheus + Grafana + Alertmanager
# ---------------------------------------------------------------------------

resource "kind_cluster" "this" {
  # node_image empty = the kind provider's own tested default Kubernetes version
  name            = var.cluster_name
  node_image      = var.kubernetes_version == "" ? null : "kindest/node:${var.kubernetes_version}"
  wait_for_ready  = true
  kubeconfig_path = pathexpand("~/.kube/config") # so kubectl works right away

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"
      # host port -> kind node NodePort -> service.
      # One fixed port per UI works the same locally and in Codespaces
      # (Codespaces gives every forwarded port its own HTTPS link).
      dynamic "extra_port_mappings" {
        for_each = var.ports
        content {
          container_port = extra_port_mappings.value.node_port
          host_port      = extra_port_mappings.value.host_port
          protocol       = "TCP"
        }
      }
    }
  }
}

provider "helm" {
  kubernetes = {
    host                   = kind_cluster.this.endpoint
    client_certificate     = kind_cluster.this.client_certificate
    client_key             = kind_cluster.this.client_key
    cluster_ca_certificate = kind_cluster.this.cluster_ca_certificate
  }
}

resource "helm_release" "traefik" {
  name             = "traefik"
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = var.chart_versions["traefik"]
  namespace        = "traefik"
  create_namespace = true
  values           = [file("${path.module}/values/traefik.yaml")]
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.chart_versions["argocd"]
  namespace        = "argocd"
  create_namespace = true
  values           = [file("${path.module}/values/argocd.yaml")]
  depends_on       = [helm_release.traefik]
}

resource "helm_release" "monitoring" {
  name             = "monitoring"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.chart_versions["monitoring"]
  namespace        = "monitoring"
  create_namespace = true
  timeout          = 900
  values = [
    file("${path.module}/values/monitoring.yaml"),
    # Behind the Codespaces HTTPS proxy Grafana must know its public URL,
    # otherwise its CSRF check rejects the login ("origin not allowed").
    var.grafana_root_url == "" ? "{}" : yamlencode({
      grafana = {
        "grafana.ini" = {
          server   = { root_url = var.grafana_root_url }
          security = { csrf_trusted_origins = trimprefix(var.grafana_root_url, "https://") }
        }
      }
    }),
  ]

  set_sensitive = [{
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }]
  depends_on = [helm_release.traefik]
}
