# Makefile for Proxy Builder (Sing-box)
# Sing-box 原生模式代理服务管理

.PHONY: all uuid short-id password reality-key setup-wif setup-firewall check-scripts upload-env help

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
	@echo "🚀 Deployment Setup:"
	@echo "  make setup-wif         - Setup WIF for an environment (interactive)"
	@echo "  make upload-env        - Upload .env to GitHub Environment Secrets"
	@echo "  make setup-firewall    - Configure firewall rules for service ports"
	@echo "  make check-scripts     - Check all shell scripts syntax"
	@echo ""

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
# Deployment Setup
# ============================================================

setup-wif:
	@chmod +x scripts/setup-wif.sh
	@./scripts/setup-wif.sh

upload-env:
	@chmod +x scripts/upload-env.sh
	@./scripts/upload-env.sh

setup-firewall:
	@chmod +x scripts/setup-firewall.sh
	@./scripts/setup-firewall.sh

