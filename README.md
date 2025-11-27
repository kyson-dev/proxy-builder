# 代理服务部署指南

## 📁 项目结构
```
proxy-builder/
├── .env                 # 环境变量（敏感信息）
├── docker-compose.yml   # Docker 服务配置
├── deploy.sh           # 一键部署脚本
├── change-domain.sh    # 域名替换工具
├── README.md           # 本文档
├── .github/
│   └── workflows/
│       └── deploy.yml  # GitHub Actions 自动部署配置
├── docs/
│   ├── github-secrets-setup.md    # GitHub Secrets 配置指南
│   └── deployment-workflow.md     # 部署流程详解
├── nginx/
│   └── nginx.conf      # Nginx 配置
├── sing-box/
│   ├── config.json.template # Sing-box 配置模板
│   └── entrypoint.sh   # 容器启动脚本
├── webroot/            # Certbot HTTP-01 验证目录
└── certs/              # 证书存储目录（自动生成）
```

## 🚀 部署步骤

本项目支持两种部署方式：

### 方式 1: GitHub Actions 自动部署（推荐）

通过 GitHub Actions 实现自动化部署，支持零停机更新。

#### 配置步骤：

1. **配置 GitHub Secrets**
   - 查看详细指南：[docs/github-secrets-setup.md](docs/github-secrets-setup.md)
   - 需要配置：SSH 密钥、VM 信息、域名、证书邮箱、代理凭证等

2. **推送代码触发部署**
   ```bash
   git add .
   git commit -m "Update configuration"
   git push origin main
   ```

3. **查看部署进度**
   - 在 GitHub 仓库的 **Actions** 标签页查看部署状态
   - 首次部署会自动运行 `deploy.sh` 申请证书
   - 后续更新会进行零停机重启

📖 **了解更多**：查看 [部署流程详解](docs/deployment-workflow.md)

---

### 方式 2: 手动部署

适合本地测试或不使用 GitHub Actions 的场景。

### 1. 配置环境变量
复制 `.env` 文件并修改其中的配置：
```bash
# 域名
DOMAIN=kyson.site
EMAIL=admin@kyson.site

# VLESS Reality
VLESS_UUID=your-uuid-here
REALITY_PRIVATE_KEY=your-private-key-here
REALITY_SHORT_ID=your-short-id-here

# Hysteria2 / TUIC
PROXY_PASSWORD=your-secure-password-here
```

### 2. 生成新凭证（可选）
如果需要生成新的 UUID 或 Reality 密钥：
```bash
# 生成 UUID
uuidgen

# 生成 Reality 密钥对
docker run --rm ghcr.io/sagernet/sing-box:latest generate reality-keypair

# 生成随机密码
openssl rand -hex 16
```

### 3. 一键部署
```bash
./deploy.sh
```

## 📊 查看状态和日志

### 查看服务状态
```bash
docker compose ps
```

### 查看所有日志
```bash
docker compose logs -f
```

## 📱 客户端配置

### VLESS + Reality
```
协议:        VLESS
地址:        ${DOMAIN}
端口:        443
UUID:        ${VLESS_UUID}
Flow:        xtls-rprx-vision
传输:        TCP
TLS:         Reality
SNI:         www.microsoft.com
Public Key:  (使用生成的公钥)
Short ID:    ${REALITY_SHORT_ID}
```

### Hysteria2
```
协议:        Hysteria2
地址:        ${DOMAIN}
端口:        443
密码:        ${PROXY_PASSWORD}
TLS:         启用
SNI:         ${DOMAIN}
```

### TUIC
```
协议:        TUIC
地址:        ${DOMAIN}
端口:        5443
UUID:        ${VLESS_UUID}
密码:        ${PROXY_PASSWORD}
拥塞控制:    BBR
TLS:         启用
SNI:         ${DOMAIN}
```

## ⚠️ 注意事项

1. **安全性**: `.env` 文件包含敏感信息，请勿分享或提交到公共仓库。
2. **DNS 配置**: 确保域名 A 记录指向服务器 IP。
3. **防火墙**: 开放端口 80, 443, 5443。
