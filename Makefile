# Makefile for Proxy Builder (Sing-box)
# Sing-box 原生模式代理服务管理

.PHONY: all uuid short-id password reality-key secrets-init secrets-import-production secrets-publish subscription-url user-add user-enable user-disable user-rotate user-protocol-enable user-protocol-disable github-reset github-configure github-clean-production-legacy github-audit bootstrap validate infra-plan infra-apply deploy destroy help

# Accept short operator-facing aliases while keeping canonical names everywhere
# that forms part of a path, Terraform state, or GitHub Environment identity.
CANONICAL_ENV = $(if $(filter dev,$(ENV)),development,$(if $(filter prod,$(ENV)),production,$(ENV)))

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
	@echo "  ENV accepts dev|development or prod|production"
	@echo "  make secrets-init ENV=dev|prod USER=..."
	@echo "  make secrets-import-production"
	@echo "  make user-add|user-enable|user-disable|user-rotate ENV=dev|prod USER=..."
	@echo "  make user-protocol-enable|user-protocol-disable ENV=dev|prod USER=... PROTOCOL=vless|hysteria2"
	@echo "  make secrets-publish ENV=dev|prod"
	@echo "  make subscription-url ENV=dev|prod USER=... [FORMAT=base64|clash]"
	@echo ""
	@echo "🏗️  OpenTofu Platform:"
	@echo "  make bootstrap ENV=dev|prod"
	@echo "  make github-reset ENV=dev CONFIRM=owner/repo:development"
	@echo "  make github-configure ENV=dev|prod"
	@echo "  make github-clean-production-legacy CONFIRM=owner/repo:production"
	@echo "  make github-audit ENV=dev|prod"
	@echo "  make validate"
	@echo "  make infra-plan ENV=dev|prod [STACK=bootstrap|platform]"
	@echo "  make infra-apply ENV=dev|prod [STACK=bootstrap|platform]"
	@echo "  make deploy ENV=dev|prod [GIT_REF=<ref>]"
	@echo "  make destroy ENV=dev|prod STACK=platform"


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
	@ENV="$(CANONICAL_ENV)" USER="$(USER)" ./scripts/secrets/init.sh

secrets-import-production:
	@./scripts/secrets/import-production.sh

user-add:
	@ENV="$(CANONICAL_ENV)" USER="$(USER)" ./scripts/secrets/manage-user.sh add

user-enable:
	@ENV="$(CANONICAL_ENV)" USER="$(USER)" ./scripts/secrets/manage-user.sh enable

user-disable:
	@ENV="$(CANONICAL_ENV)" USER="$(USER)" ./scripts/secrets/manage-user.sh disable

user-rotate:
	@ENV="$(CANONICAL_ENV)" USER="$(USER)" ./scripts/secrets/manage-user.sh rotate

user-protocol-enable:
	@ENV="$(CANONICAL_ENV)" USER="$(USER)" PROTOCOL="$(PROTOCOL)" ./scripts/secrets/manage-user.sh protocol-enable

user-protocol-disable:
	@ENV="$(CANONICAL_ENV)" USER="$(USER)" PROTOCOL="$(PROTOCOL)" ./scripts/secrets/manage-user.sh protocol-disable

secrets-publish:
	@./scripts/github/publish-secrets.sh --environment "$(CANONICAL_ENV)" --secret-dir ".secrets/$(CANONICAL_ENV)"

subscription-url:
	@ENV="$(CANONICAL_ENV)" USER="$(USER)" FORMAT="$(or $(FORMAT),base64)" ./scripts/secrets/subscription-url.sh

# ============================================================
# OpenTofu Platform
# ============================================================

bootstrap:
	@ENV="$(CANONICAL_ENV)" ./scripts/infra/bootstrap-state.sh

github-configure:
	@./scripts/github/configure.sh --environment "$(CANONICAL_ENV)"

github-clean-production-legacy:
	@./scripts/github/clear-legacy-production-secrets.sh --confirm "$(CONFIRM)"

github-reset:
	@./scripts/github/reset-environment.sh --environment "$(CANONICAL_ENV)" --confirm "$(CONFIRM)"

github-audit:
	@./scripts/github/audit.sh --environment "$(CANONICAL_ENV)"

validate:
	@./scripts/validate.sh

infra-plan:
	@ENV="$(CANONICAL_ENV)" STACK="$(or $(STACK),platform)" ./scripts/infra/tofu-stack.sh plan

infra-apply:
	@ENV="$(CANONICAL_ENV)" STACK="$(or $(STACK),platform)" ./scripts/infra/tofu-stack.sh apply

deploy:
	@ENV="$(CANONICAL_ENV)" GIT_REF="$(GIT_REF)" ./scripts/github/dispatch-deploy.sh

destroy:
	@ENV="$(CANONICAL_ENV)" CONFIRM_PROJECT_ID="$(CONFIRM_PROJECT_ID)" ./scripts/infra/destroy-platform.sh
