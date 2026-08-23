# Makefile for Proxy Builder (Sing-box)
# Sing-box 原生模式代理服务管理

.PHONY: all uuid short-id password reality-key bootstrap validate infra-plan infra-apply deploy destroy help

help:
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "Proxy Builder (Sing-box Native) - Available Commands"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@echo "🔐 Credential Generation:"
	@echo "  make uuid              - Generate a random UUID"
	@echo "  make short-id          - Generate a random 8-character hex ID"
	@echo "  make password          - Generate a random secure password"
	@echo "  make reality-key       - Generate REALITY key pair (uses Docker)"
	@echo ""
	@echo "🏗️  OpenTofu Platform:"
	@echo "  make bootstrap ENV=development|production"
	@echo "  make validate"
	@echo "  make infra-plan ENV=... [STACK=bootstrap|platform]"
	@echo "  make infra-apply ENV=... [STACK=bootstrap|platform]"
	@echo "  make deploy ENV=... [GIT_REF=<ref>]"
	@echo "  make destroy ENV=... STACK=platform"


# ============================================================
# Credential Generation
# ============================================================

uuid:
	@uuidgen | tr '[:upper:]' '[:lower:]'

short-id:
	@openssl rand -hex 4

password:
	@openssl rand -base64 32

reality-key:
	@echo "Generating REALITY key pair using sing-box docker image..."
	@docker run --rm ghcr.io/sagernet/sing-box generate reality-keypair

# ============================================================
# OpenTofu Platform
# ============================================================

bootstrap:
	@ENV="$(ENV)" ./scripts/infra/bootstrap-state.sh

validate:
	@./scripts/validate.sh

infra-plan:
	@ENV="$(ENV)" STACK="$(or $(STACK),platform)" ./scripts/infra/tofu-stack.sh plan

infra-apply:
	@ENV="$(ENV)" STACK="$(or $(STACK),platform)" ./scripts/infra/tofu-stack.sh apply

deploy:
	@ENV="$(ENV)" GIT_REF="$(GIT_REF)" ./scripts/github/dispatch-deploy.sh

destroy:
	@ENV="$(ENV)" CONFIRM_PROJECT_ID="$(CONFIRM_PROJECT_ID)" ./scripts/infra/destroy-platform.sh
