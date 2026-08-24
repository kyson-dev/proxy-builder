# Makefile for Proxy Builder (Sing-box)
# Sing-box 原生模式代理服务管理

.PHONY: all uuid short-id password reality-key secrets-init secrets-publish subscription-url user-add user-enable user-disable user-rotate github-reset github-configure github-audit bootstrap validate infra-plan infra-apply deploy destroy help

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
	@echo "  make secrets-init ENV=... USER=..."
	@echo "  make user-add|user-enable|user-disable|user-rotate ENV=... USER=..."
	@echo "  make secrets-publish ENV=..."
	@echo "  make subscription-url ENV=... USER=... [FORMAT=base64|clash]"
	@echo ""
	@echo "🏗️  OpenTofu Platform:"
	@echo "  make bootstrap ENV=development|production"
	@echo "  make github-reset ENV=development CONFIRM=owner/repo:development"
	@echo "  make github-configure ENV=development|production"
	@echo "  make github-audit ENV=development|production"
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

secrets-init:
	@ENV="$(ENV)" USER="$(USER)" ./scripts/secrets/init.sh

user-add:
	@ENV="$(ENV)" USER="$(USER)" ./scripts/secrets/manage-user.sh add

user-enable:
	@ENV="$(ENV)" USER="$(USER)" ./scripts/secrets/manage-user.sh enable

user-disable:
	@ENV="$(ENV)" USER="$(USER)" ./scripts/secrets/manage-user.sh disable

user-rotate:
	@ENV="$(ENV)" USER="$(USER)" ./scripts/secrets/manage-user.sh rotate

secrets-publish:
	@./scripts/github/publish-secrets.sh --environment "$(ENV)" --secret-dir ".secrets/$(ENV)"

subscription-url:
	@ENV="$(ENV)" USER="$(USER)" FORMAT="$(or $(FORMAT),base64)" ./scripts/secrets/subscription-url.sh

# ============================================================
# OpenTofu Platform
# ============================================================

bootstrap:
	@ENV="$(ENV)" ./scripts/infra/bootstrap-state.sh

github-configure:
	@./scripts/github/configure.sh --environment "$(ENV)"

github-reset:
	@./scripts/github/reset-environment.sh --environment "$(ENV)" --confirm "$(CONFIRM)"

github-audit:
	@./scripts/github/audit.sh --environment "$(ENV)"

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
