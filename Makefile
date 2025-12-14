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
	@echo "📦 Configuration Push:"
	@echo "  make push-config-prod  - Convert singbox.config.json and push to production"
	@echo "  make push-config-dev   - Convert singbox.config.json and push to development"
	@echo ""
	@echo "🛠️  Utilities:"
	@echo "  make generate-cert     - Generate self-signed certificate for Hysteria2"
	@echo "  make check-cert        - Check certificate validity and information"
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

# ============================================================
# Configuration Push (上传变量配置)
# ============================================================

# Push production config
push-config-prod:
	@if [ ! -f vars.production.json ]; then \
		echo "❌ vars.production.json not found!"; \
		echo "   Please copy vars.production.example.json to vars.production.json and fill in your values."; \
		exit 1; \
	fi
	@echo "📦 Pushing vars.production.json to 'production' environment..."
	@gh secret set VARS_JSON --env production < vars.production.json
	@echo ""
	@echo "✅ Production variables uploaded!"

# Push development config
push-config-dev:
	@if [ ! -f vars.development.json ]; then \
		echo "❌ vars.development.json not found!"; \
		echo "   Please copy vars.development.example.json to vars.development.json and fill in your values."; \
		exit 1; \
	fi
	@echo "📦 Pushing vars.development.json to 'development' environment..."
	@gh secret set VARS_JSON --env development < vars.development.json
	@echo ""
	@echo "✅ Development variables uploaded!"

# ============================================================
# Generate certificate for Hysteria2
# ============================================================

generate-cert:
	@echo "🔐 生成 Hysteria2 自签名证书..."
	@mkdir -p sing-box/certs
	@if [ -f sing-box/certs/cert.pem ] || [ -f sing-box/certs/key.pem ]; then \
		echo "⚠️  警告: 证书文件已存在"; \
		read -p "是否覆盖? (y/N) " -n 1 -r; \
		echo; \
		if [[ ! $$REPLY =~ ^[Yy]$$ ]]; then \
			echo "❌ 已取消"; \
			exit 1; \
		fi; \
		rm -f sing-box/certs/cert.pem sing-box/certs/key.pem; \
	fi
	@openssl req -x509 -nodes -newkey rsa:2048 \
		-keyout sing-box/certs/key.pem \
		-out sing-box/certs/cert.pem \
		-subj "/CN=bing.com" \
		-days 36500 >/dev/null 2>&1 || \
	(openssl ecparam -name prime256v1 -genkey -noout -out sing-box/certs/key.pem 2>/dev/null && \
	openssl req -new -x509 -key sing-box/certs/key.pem \
		-out sing-box/certs/cert.pem \
		-subj "/CN=bing.com" \
		-days 36500 >/dev/null 2>&1)
	@if [ -f sing-box/certs/cert.pem ]; then \
		chmod 644 sing-box/certs/cert.pem; \
		chmod 600 sing-box/certs/key.pem; \
		echo "✅ 证书生成成功"; \
		echo "📋 CN: bing.com"; \
		echo "📅 有效期: 100 年"; \
	else \
		echo "❌ 证书生成失败"; \
		exit 1; \
	fi

check-cert:
	@if [ ! -f sing-box/certs/cert.pem ]; then \
		echo "❌ 证书不存在: sing-box/certs/cert.pem"; \
		exit 1; \
	fi
	@echo "🔍 证书信息:"
	@echo "📋 CN: $$(openssl x509 -in sing-box/certs/cert.pem -noout -subject 2>/dev/null | sed -n 's/.*CN=\([^,]*\).*/\1/p')"
	@echo "📅 生效时间: $$(openssl x509 -in sing-box/certs/cert.pem -noout -startdate 2>/dev/null | cut -d= -f2)"
	@echo "📅 过期时间: $$(openssl x509 -in sing-box/certs/cert.pem -noout -enddate 2>/dev/null | cut -d= -f2)"
	@openssl x509 -in sing-box/certs/cert.pem -noout -checkend 86400 >/dev/null 2>&1 && \
		echo "✅ 证书有效" || echo "⚠️  证书已过期或即将过期"
