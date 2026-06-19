# Convenience wrappers. Most targets operate on the prod env (envs/prod).
# Override the env:  make plan ENV=staging

ENV ?= prod
ENV_DIR := envs/$(ENV)

.PHONY: help bootstrap init plan plan-check apply destroy fmt validate clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

bootstrap: ## Create the S3 state bucket (run once, local state)
	cd bootstrap && terraform init && terraform apply

init: ## terraform init for $(ENV)
	cd $(ENV_DIR) && terraform init

plan: ## terraform plan for $(ENV) (real: S3 backend + AWS creds)
	cd $(ENV_DIR) && terraform plan

# Offline code-complete gate. AWS provider v6 always calls STS:GetCallerIdentity and
# backend.tf points at S3, so a plain `terraform plan` can't run without AWS access.
# This target writes a transient *_override.tf (local backend + stubbed AWS provider),
# runs fmt/validate/plan with zero AWS/S3 access, then always removes it (EXIT trap).
# providers.tf and backend.tf stay clean for real applies (D-07).
plan-check: ## Offline gate for $(ENV): fmt -check, validate, non-empty plan (no AWS/S3 access)
	terraform fmt -check -recursive
	@cd $(ENV_DIR) && \
		printf '%s\n' \
			'terraform {' \
			'  backend "local" {}' \
			'}' \
			'provider "aws" {' \
			'  skip_credentials_validation = true' \
			'  skip_requesting_account_id  = true' \
			'  skip_metadata_api_check     = true' \
			'  access_key                  = "dummy"' \
			'  secret_key                  = "dummy"' \
			'}' > gate_override.tf && \
		trap 'rm -f gate_override.tf terraform.tfstate terraform.tfstate.backup; rm -rf .terraform .terraform.lock.hcl' EXIT && \
		terraform init -reconfigure -input=false >/dev/null && \
		terraform validate && \
		terraform plan -input=false

apply: ## terraform apply for $(ENV)
	cd $(ENV_DIR) && terraform apply

destroy: ## terraform destroy for $(ENV)
	cd $(ENV_DIR) && terraform destroy

fmt: ## Format all .tf files
	terraform fmt -recursive

validate: ## Validate $(ENV)
	cd $(ENV_DIR) && terraform validate

clean: ## Remove local .terraform dirs
	find . -type d -name .terraform -prune -exec rm -rf {} +
