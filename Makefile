.PHONY: help init plan apply destroy setup status logs clean generate migrate-state

# Default target
help:
	@echo "OpenClaw Kubernetes Deployment"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Terraform Commands:"
	@echo "  init           Initialize Terraform"
	@echo "  plan           Preview Terraform changes"
	@echo "  apply          Deploy with Terraform"
	@echo "  destroy        Destroy all resources"
	@echo "  migrate-state  Migrate state from old (flat) structure"
	@echo ""
	@echo "Script Commands:"
	@echo "  setup          Run interactive setup script"
	@echo "  status         Show deployment status"
	@echo "  logs           Follow gateway logs"
	@echo ""
	@echo "Utility Commands:"
	@echo "  generate       Generate bundled manifest"
	@echo "  clean          Remove generated files"

# Terraform commands (run from terraform/ directory)
init:
	cd terraform && terraform init

plan:
	cd terraform && terraform plan

apply:
	cd terraform && terraform apply

destroy:
	cd terraform && terraform destroy

# Script wrappers
setup:
	./scripts/setup.sh

status:
	./scripts/tools.sh status

logs:
	./scripts/tools.sh logs

generate:
	./scripts/generate-manifest.sh

clean:
	rm -f manifests/bundled/openclaw-k8s.yaml

# Migrate state from old (flat) structure to new terraform/ directory
migrate-state:
	@echo "==> Migrating Terraform state from old structure..."
	@if [ -f "terraform.tfstate" ]; then \
		echo "    Moving terraform.tfstate..."; \
		mv terraform.tfstate terraform/; \
	fi
	@if [ -f "terraform.tfstate.backup" ]; then \
		echo "    Moving terraform.tfstate.backup..."; \
		mv terraform.tfstate.backup terraform/; \
	fi
	@if [ -d ".terraform" ]; then \
		echo "    Moving .terraform/..."; \
		mv .terraform terraform/; \
	fi
	@if [ -f ".terraform.lock.hcl" ]; then \
		echo "    Moving .terraform.lock.hcl..."; \
		mv .terraform.lock.hcl terraform/; \
	fi
	@if [ -f "terraform.tfvars" ]; then \
		echo "    Moving terraform.tfvars..."; \
		mv terraform.tfvars terraform/; \
	fi
	@echo "==> Running terraform init..."
	cd terraform && terraform init
	@echo ""
	@echo "==> Migration complete! Verify with:"
	@echo "    cd terraform && terraform plan"
