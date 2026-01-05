# Makefile for Proxy Builder (S-UI)
# S-UI Web Panel 管理代理服务

.PHONY: all uuid short-id password reality-key setup-wif setup-firewall rollback check-scripts help generate-cert check-cert

help:
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "Proxy Builder (S-UI) - Available Commands"
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
	@echo "  make setup-firewall    - Configure firewall rules for service ports"
	@echo "  make rollback          - Rollback to previous version (remote)"
	@echo "  make check-scripts     - Check all shell scripts syntax"
	@echo ""
	@echo "️  Utilities:"
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

setup-firewall:
	@chmod +x scripts/setup-firewall.sh
	@./scripts/setup-firewall.sh

# ============================================================
# Generate certificate for Hysteria2
# ============================================================

generate-cert:
	@echo "🔐 生成 Hysteria2 自签名证书..."
	@mkdir -p s-ui/cert
	@if [ -f s-ui/cert/cert.pem ] || [ -f s-ui/cert/key.pem ]; then \
		echo "⚠️  警告: 证书文件已存在"; \
		read -p "是否覆盖? (y/N) " -n 1 -r; \
		echo; \
		if [[ ! $$REPLY =~ ^[Yy]$$ ]]; then \
			echo "❌ 已取消"; \
			exit 1; \
		fi; \
		rm -f s-ui/cert/cert.pem s-ui/cert/key.pem; \
	fi
	@openssl req -x509 -nodes -newkey rsa:2048 \
		-keyout s-ui/cert/key.pem \
		-out s-ui/cert/cert.pem \
		-subj "/CN=bing.com" \
		-days 36500 >/dev/null 2>&1 || \
	(openssl ecparam -name prime256v1 -genkey -noout -out s-ui/cert/key.pem 2>/dev/null && \
	openssl req -new -x509 -key s-ui/cert/key.pem \
		-out s-ui/cert/cert.pem \
		-subj "/CN=bing.com" \
		-days 36500 >/dev/null 2>&1)
	@if [ -f s-ui/cert/cert.pem ]; then \
		chmod 644 s-ui/cert/cert.pem; \
		chmod 600 s-ui/cert/key.pem; \
		echo "✅ 证书生成成功"; \
		echo "📋 CN: bing.com"; \
		echo "📅 有效期: 100 年"; \
	else \
		echo "❌ 证书生成失败"; \
		exit 1; \
	fi

check-cert:
	@if [ ! -f s-ui/cert/cert.pem ]; then \
		echo "❌ 证书不存在: s-ui/cert/cert.pem"; \
		exit 1; \
	fi
	@echo "🔍 证书信息:"
	@echo "📋 CN: $$(openssl x509 -in s-ui/cert/cert.pem -noout -subject 2>/dev/null | sed -n 's/.*CN=\([^,]*\).*/\1/p')"
	@echo "📅 生效时间: $$(openssl x509 -in s-ui/cert/cert.pem -noout -startdate 2>/dev/null | cut -d= -f2)"
	@echo "📅 过期时间: $$(openssl x509 -in s-ui/cert/cert.pem -noout -enddate 2>/dev/null | cut -d= -f2)"
	@openssl x509 -in s-ui/cert/cert.pem -noout -checkend 86400 >/dev/null 2>&1 && \
		echo "✅ 证书有效" || echo "⚠️  证书已过期或即将过期"
