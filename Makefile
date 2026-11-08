# Shortcuts for every phase of the project.  Run `make help`.
.DEFAULT_GOAL := help
SHELL := /bin/bash

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n",$$1,$$2}'

# In Codespaces, Grafana must know its public HTTPS URL (see terraform/main.tf).
ifdef CODESPACE_NAME
GRAFANA_URL := https://$(CODESPACE_NAME)-3000.$(GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN)
TF_EXTRA := -var grafana_root_url=$(GRAFANA_URL)
endif

# ---- Phase 0: setup -------------------------------------------------------
setup: ## Codespaces: fill in usernames + write jenkins/.env from secrets
	bash scripts/setup-codespace.sh

urls: ## Print the URL of every UI
	@bash scripts/urls.sh

# ---- Phase 1: app ---------------------------------------------------------
venv: ## Create a Python virtualenv with dev deps
	python3 -m venv .venv && .venv/bin/pip install -q -r app/requirements-dev.txt

test: ## Lint + unit tests (locally)
	cd app && ../.venv/bin/ruff check src tests && ../.venv/bin/pytest -q tests

run: ## Run the app locally on :8000
	cd app/src && ../../.venv/bin/python app.py

docker-test: ## Lint + tests inside Docker (exactly what CI does)
	docker build --target test -t taskapp-test app/

compose-up: ## Build + run with Docker Compose on :8000
	docker compose up --build -d

compose-down: ## Stop Docker Compose
	docker compose down

# ---- Phase 2: Ansible -----------------------------------------------------
ansible: ## Install tools + start Jenkins
	cd ansible && ansible-galaxy collection install -r requirements.yml && ansible-playbook site.yml

# ---- Phase 3: Terraform ---------------------------------------------------
infra: ## Create kind cluster + Traefik + Argo CD + Prometheus/Grafana
	cd terraform && terraform init && terraform apply $(TF_EXTRA)

infra-destroy: ## Destroy everything Terraform created
	cd terraform && terraform destroy $(TF_EXTRA)

# ---- Phase 4: Helm / Argo CD ----------------------------------------------
helm-lint: ## Lint + render the chart
	helm lint helm/taskapp && helm template taskapp helm/taskapp > /dev/null && echo "chart OK"

argocd-app: ## Register the app with Argo CD (one time)
	kubectl apply -f argocd/taskapp-application.yaml

argocd-password: ## Print the initial Argo CD admin password
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo

# ---- Phase 5: traffic -----------------------------------------------------
traffic: ## Send steady traffic from your laptop (Ctrl+C to stop)
	python3 helm/taskapp/files/loadgen.py --url http://localhost:8081 --rps 20

spike: ## 60-second traffic spike
	python3 helm/taskapp/files/loadgen.py --url http://localhost:8081 --rps 150 --duration 60

status: ## What is running in the cluster?
	kubectl get applications -n argocd; kubectl get pods -n taskapp -o wide
