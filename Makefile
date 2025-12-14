# Makefile for Proxy Builder
# 支持多环境部署 (production / development)

.PHONY: all uuid short-id password reality-key setup-wif push-env push-env-prod push-env-dev help

help:
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "Proxy Builder - Available Commands"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@echo "🔐 Credential Generation:"
	@echo "  make uuid              - Generate a random UUID"
	@echo "  make short-id          - Generate a random 8-character hex ID"
	@echo "  make password          - Generate a random secure password"
	@echo "  make reality-key       - Generate REALITY key pair (uses Docker)"
	@echo ""
	@echo "🚀 Deployment Setup:"
	@echo "  make setup-wif         - Setup WIF for an environment (interactive)"
	@echo ""
	@echo "📦 Environment Variables:"
	@echo "  make push-env          - Push .env to repository secrets (legacy)"
	@echo "  make push-env-prod     - Push .env.production to production environment"
	@echo "  make push-env-dev      - Push .env.development to development environment"
	@echo ""
	@echo "🛠️  Utilities:"
	@echo "  make change-domain     - Change domain name in config"
	@echo ""

# ============================================================
# Credential Generation
# ============================================================

uuid:
	@uuidgen | tr '[:upper:]' '[:lower:]'

short-id:
	@openssl rand -hex 4

password:
	@openssl rand -base64 16

reality-key:
	@echo "Generating REALITY key pair using sing-box docker image..."
	@docker run --rm ghcr.io/sagernet/sing-box generate reality-keypair

# ============================================================
# Deployment Setup
# ============================================================

setup-wif:
	@chmod +x scripts/setup-wif.sh
	@./scripts/setup-wif.sh

# ============================================================
# Environment Variables Push
# ============================================================

# Legacy: Push to repository level (not recommended for multi-env)
push-env:
	@if [ ! -f .env ]; then echo "❌ .env file not found!"; exit 1; fi
	@echo "⚠️  Warning: This pushes to repository-level secrets (not environment-specific)"
	@echo "   For multi-environment setup, use: make push-env-prod or make push-env-dev"
	@echo ""
	@read -p "Continue anyway? (y/n): " confirm && [ "$$confirm" = "y" ] || exit 1
	@echo "Pushing secrets from .env to GitHub..."
	@gh secret set -f .env
	@echo "✅ Done."

# Push to production environment
push-env-prod:
	@if [ ! -f .env.production ]; then \
		echo "❌ .env.production file not found!"; \
		echo "   Please create .env.production with your production configuration."; \
		exit 1; \
	fi
	@echo "📦 Pushing secrets from .env.production to 'production' environment..."
	@echo ""
	@while IFS='=' read -r key value; do \
		if [ -n "$$key" ] && [ "$${key:0:1}" != "#" ]; then \
			echo "  Setting $$key..."; \
			gh secret set "$$key" --env production --body "$$value"; \
		fi; \
	done < .env.production
	@echo ""
	@echo "✅ Production environment secrets updated!"

# Push to development environment
push-env-dev:
	@if [ ! -f .env.development ]; then \
		echo "❌ .env.development file not found!"; \
		echo "   Please create .env.development with your development configuration."; \
		exit 1; \
	fi
	@echo "📦 Pushing secrets from .env.development to 'development' environment..."
	@echo ""
	@while IFS='=' read -r key value; do \
		if [ -n "$$key" ] && [ "$${key:0:1}" != "#" ]; then \
			echo "  Setting $$key..."; \
			gh secret set "$$key" --env development --body "$$value"; \
		fi; \
	done < .env.development
	@echo ""
	@echo "✅ Development environment secrets updated!"

# ============================================================
# Utilities
# ============================================================

change-domain:
	@chmod +x scripts/change-domain.sh
	@./scripts/change-domain.sh
