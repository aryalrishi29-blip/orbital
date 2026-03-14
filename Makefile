.DEFAULT_GOAL := help
.PHONY: help up down build logs shell migrate test test-cov lint format \
        tf-init tf-plan tf-apply tf-destroy clean

# ── Colours ───────────────────────────────────────────────────
CYAN  := \033[36m
RESET := \033[0m

help: ## Show available commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS=":.*?## "}; {printf "  $(CYAN)%-18s$(RESET) %s\n", $$1, $$2}'

# ── Docker Compose ────────────────────────────────────────────
up: ## Start Django + Postgres (builds image first)
	docker compose up --build

down: ## Stop all containers and remove volumes
	docker compose down -v

build: ## Build the Docker image only
	docker compose build

logs: ## Tail logs from the web container
	docker compose logs -f web

shell: ## Open a Django shell inside the running container
	docker compose exec web python manage.py shell

migrate: ## Run database migrations inside the running container
	docker compose exec web python manage.py migrate --noinput

# ── Testing ───────────────────────────────────────────────────
test: ## Run the full test suite
	cd app && python manage.py test myapp --verbosity=2

test-cov: ## Run tests and open HTML coverage report
	cd app && coverage run manage.py test myapp --verbosity=2
	cd app && coverage report --fail-under=80
	cd app && coverage html -d htmlcov
	@echo ""
	@echo "  Open: app/htmlcov/index.html"

# ── Code quality ──────────────────────────────────────────────
lint: ## Run flake8 linter
	flake8 app/ --max-line-length=100 --exclude=app/myapp/migrations

format: ## Auto-format with black + isort
	black app/
	isort app/

format-check: ## Check formatting without modifying files
	black --check --diff app/
	isort --check-only --diff app/

# ── Terraform ─────────────────────────────────────────────────
tf-init: ## Initialise Terraform (run once)
	cd terraform && terraform init

tf-plan: ## Preview infrastructure changes
	cd terraform && terraform plan

tf-apply: ## Create / update AWS infrastructure
	cd terraform && terraform apply

tf-destroy: ## Destroy all AWS resources (careful!)
	cd terraform && terraform destroy

# ── Housekeeping ──────────────────────────────────────────────
clean: ## Remove caches, coverage artefacts, and compiled files
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -name "*.pyc" -delete 2>/dev/null || true
	rm -rf app/.coverage app/htmlcov app/coverage.xml app/staticfiles
	@echo "Clean!"

# ── Kubernetes ────────────────────────────────────────────────
k8s-apply-staging: ## Apply K8s manifests to staging
	kubectl apply -k k8s/overlays/staging

k8s-apply-prod: ## Apply K8s manifests to production
	kubectl apply -k k8s/overlays/production

k8s-status: ## Show pod/deployment status in django-app namespace
	kubectl get pods,deployments,hpa,pdb -n django-app

k8s-logs: ## Tail logs from django-app pods
	kubectl logs -n django-app -l app=django-app -f --tail=100

k8s-rollout-status: ## Check ArgoCD Rollout status
	kubectl argo rollouts status django-app -n django-app

k8s-rollout-promote: ## Manually promote blue-green rollout (green → active)
	kubectl argo rollouts promote django-app -n django-app

k8s-rollback: ## Abort rollout and roll back to previous version
	kubectl argo rollouts abort django-app -n django-app

# ── ArgoCD ────────────────────────────────────────────────────
argocd-install: ## Bootstrap ArgoCD on cluster
	bash gitops/argocd/install-argocd.sh

argocd-apply: ## Apply ArgoCD Application manifests
	kubectl apply -f gitops/apps/

argocd-ui: ## Port-forward ArgoCD UI to localhost:8080
	kubectl port-forward svc/argocd-server -n argocd 8080:443

# ── Observability ─────────────────────────────────────────────
obs-install: ## Install kube-prometheus-stack via Helm
	bash observability/prometheus/install.sh

obs-apply: ## Apply ServiceMonitor and alert rules
	kubectl apply -f observability/prometheus/service-monitor.yaml
	kubectl apply -f observability/prometheus/alert-rules.yaml

prometheus-ui: ## Port-forward Prometheus to localhost:9090
	kubectl port-forward svc/kube-prometheus-stack-prometheus -n observability 9090:9090

grafana-ui: ## Port-forward Grafana to localhost:3000
	kubectl port-forward svc/kube-prometheus-stack-grafana -n observability 3000:80

alertmanager-ui: ## Port-forward Alertmanager to localhost:9093
	kubectl port-forward svc/kube-prometheus-stack-alertmanager -n observability 9093:9093

# ── Service mesh (Linkerd) ────────────────────────────────────
mesh-install: ## Install Linkerd service mesh
	bash service-mesh/linkerd/install.sh

mesh-inject: ## Enable Linkerd sidecar injection on orbital namespace
	kubectl apply -f service-mesh/linkerd/namespace-inject.yaml
	kubectl apply -f service-mesh/linkerd/service-profile.yaml
	kubectl rollout restart deployment/orbital -n orbital

mesh-status: ## Check Linkerd proxy status on orbital pods
	linkerd check
	linkerd viz stat deploy/orbital -n orbital

mesh-dashboard: ## Open Linkerd Viz dashboard
	linkerd viz dashboard &

mesh-top: ## Live per-route traffic stats
	linkerd viz top deploy/orbital -n orbital

# ── Distributed tracing (OTel + Jaeger) ──────────────────────
tracing-install: ## Deploy OTel Collector + Jaeger
	kubectl apply -f tracing/otel/collector-deployment.yaml
	kubectl apply -f tracing/jaeger/jaeger.yaml
	kubectl rollout status deployment/jaeger -n tracing --timeout=120s

tracing-ui: ## Port-forward Jaeger UI to localhost:16686
	kubectl port-forward svc/jaeger-query -n tracing 16686:16686

# ── FinOps (Kubecost) ─────────────────────────────────────────
finops-install: ## Install Kubecost
	bash finops/kubecost/install.sh

finops-ui: ## Port-forward Kubecost dashboard to localhost:9090
	kubectl port-forward svc/kubecost-cost-analyzer -n kubecost 9090:9090

finops-report: ## Run weekly cost report manually
	KUBECOST_URL=http://localhost:9090 \
	SLACK_WEBHOOK=$(SLACK_WEBHOOK) \
	bash finops/reports/cost-report.sh

# ── Load testing (k6) ─────────────────────────────────────────
load-smoke: ## k6 smoke test (2 VUs, 1 min) against localhost
	k6 run load-testing/k6/scripts/api-load-test.js \
	  -e BASE_URL=http://localhost:8000 \
	  -e SCENARIO=smoke

load-test: ## k6 full load test (20→50 VUs) against localhost
	k6 run load-testing/k6/scripts/api-load-test.js \
	  -e BASE_URL=http://localhost:8000 \
	  -e SCENARIO=load

load-staging: ## k6 load test against staging
	k6 run load-testing/k6/scripts/api-load-test.js \
	  -e BASE_URL=$(STAGING_URL) \
	  -e SCENARIO=load

load-stress: ## k6 stress test (200 VUs) — find the breaking point
	k6 run load-testing/k6/scripts/api-load-test.js \
	  -e BASE_URL=$(STAGING_URL) \
	  -e SCENARIO=stress

# ── Platform (Backstage) ──────────────────────────────────────
platform-register: ## Register Orbital in Backstage catalog
	@echo "Add this URL to your Backstage app-config.yaml catalog.locations:"
	@echo "  - type: url"
	@echo "    target: https://github.com/YOUR_USERNAME/orbital/blob/main/platform/backstage/catalog/orbital-component.yaml"
