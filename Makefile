# Makefile for Proxy Builder

.PHONY: all uuid short-id password reality-key push-env help

help:
	@echo "Available commands:"
	@echo "  make uuid          - Generate a random UUID"
	@echo "  make short-id      - Generate a random 8-character hex ID (4 bytes)"
	@echo "  make password      - Generate a random secure password (16 bytes base64)"
	@echo "  make reality-key   - Generate Xray/Sing-box REALITY key pair (uses Docker)"
	@echo "  make setup-wif     - Setup GCP Workload Identity Federation for GitHub Actions"
	@echo "  make push-env      - Update GitHub repository secrets from .env file"
	@echo "  make change-domain - Change domain name in .env file"

uuid:
	@uuidgen | tr '[:upper:]' '[:lower:]'

short-id:
	@openssl rand -hex 4

password:
	@openssl rand -base64 16

reality-key:
	@echo "Generating REALITY key pair using sing-box docker image..."
	@docker run --rm ghcr.io/sagernet/sing-box generate reality-keypair

setup-wif:
	@chmod +x scripts/setup-wif.sh
	@./scripts/setup-wif.sh

push-env:
	@if [ ! -f .env ]; then echo ".env file not found!"; exit 1; fi
	@echo "Pushing secrets from .env to GitHub..."
	@gh secret set -f .env
	@echo "Done."

change-domain:
	@chmod +x scripts/change-domain.sh
	@./scripts/change-domain.sh
