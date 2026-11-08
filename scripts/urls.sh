#!/usr/bin/env bash
# Prints clickable URLs for every UI. In Codespaces each port gets its own HTTPS link.
port_url() {
  if [ -n "${CODESPACE_NAME:-}" ]; then
    echo "https://${CODESPACE_NAME}-$1.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
  else
    echo "http://localhost:$1"
  fi
}
printf "  %-14s %s\n" \
  "TaskApp"      "$(port_url 8081)" \
  "Grafana"      "$(port_url 3000)   (admin / grafana_admin_password)" \
  "Argo CD"      "$(port_url 8082)   (admin / make argocd-password)" \
  "Prometheus"   "$(port_url 9090)" \
  "Alertmanager" "$(port_url 9093)" \
  "Jenkins"      "$(port_url 8080)   (admin / JENKINS_ADMIN_PASSWORD)"
