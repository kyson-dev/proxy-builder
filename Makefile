# Makefile for Proxy Builder (Sing-box)
# Sing-box 原生模式代理服务管理

.PHONY: all uuid short-id password reality-key setup-infra setup-wif setup-vm setup-ar setup-firewall check-scripts upload-env help

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
	@echo "  make setup-infra      - One-click infra setup: WIF + VM + AR + Firewall (interactive or CI)"
	@echo "  make setup-wif        - Setup WIF for an environment (interactive)"
	@echo "  make setup-vm         - Setup GCE VM (interactive)"
	@echo "  make setup-ar         - Setup Artifact Registry (interactive)"
	@echo "  make upload-env       - Upload .env to GitHub Environment Secrets"
	@echo "  make setup-firewall   - Configure firewall rules for service ports"
	@echo "  make check-scripts    - Check all shell scripts syntax"
	@echo ""
	@echo "📁 Script Entrypoints:"
	@echo "  scripts/setup/setup-infra.sh       - One-click infra setup"
	@echo "  scripts/setup/setup-wif.sh         - Interactive WIF setup"
	@echo "  scripts/setup/setup-vm.sh          - Interactive VM setup"
	@echo "  scripts/setup/setup-ar.sh          - Interactive AR setup"
	@echo "  scripts/setup/upload-env.sh        - Interactive env upload"
	@echo "  scripts/setup/setup-firewall.sh    - Interactive firewall setup"
	@echo "  scripts/provision/provision.sh     - Host provisioning (run on VM)"
	@echo "  scripts/deploy/deploy.sh           - App deployment (run on VM)"


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

setup-infra:
	@chmod +x scripts/setup/setup-infra.sh
	@./scripts/setup/setup-infra.sh

setup-wif:
	@chmod +x scripts/setup/setup-wif.sh
	@./scripts/setup/setup-wif.sh

upload-env:
	@chmod +x scripts/setup/upload-env.sh
	@./scripts/setup/upload-env.sh

setup-firewall:
	@chmod +x scripts/setup/setup-firewall.sh
	@./scripts/setup/setup-firewall.sh

setup-vm:
	@chmod +x scripts/setup/setup-vm.sh
	@./scripts/setup/setup-vm.sh

setup-ar:
	@chmod +x scripts/setup/setup-ar.sh
	@./scripts/setup/setup-ar.sh

