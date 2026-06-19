# Convenience wrappers. Most targets operate on the prod env (envs/prod).
# Override the env:  make plan ENV=staging

ENV ?= prod
ENV_DIR := envs/$(ENV)

.PHONY: help bootstrap init plan apply destroy fmt validate clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

bootstrap: ## Create the S3 state bucket (run once, local state)
	cd bootstrap && terraform init && terraform apply

init: ## terraform init for $(ENV)
	cd $(ENV_DIR) && terraform init

plan: ## terraform plan for $(ENV)
	cd $(ENV_DIR) && terraform plan

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
