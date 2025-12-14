# 代理服务部署指南

## 📁 项目结构
```
proxy-builder/
├── .env                 # 环境变量（敏感信息）
├── Makefile            # 便捷工具命令
├── docker-compose.yml   # Docker 服务配置
├── deploy.sh           # 一键部署脚本
├── change-domain.sh    # 域名替换工具
├── README.md           # 本文档
├── .github/
│   └── workflows/
│       └── deploy.yml  # GitHub Actions WIF 自动部署
├── docs/
│   ├── WIF-SETUP-GUIDE.md    # WIF 完整配置指南
│   └── WIF-CHECKLIST.md      # WIF 快速清单
├── scripts/
│   └── setup-wif.sh    # WIF 自动配置脚本
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

通过 GitHub Actions + GCP Workload Identity Federation (WIF) 实现安全的自动化部署，支持零停机更新。

#### 快速开始（3 步）：

1. **配置 WIF（一次性）**
   ```bash
   make setup-wif
   ```
   脚本会自动配置 GCP 和 GitHub Secrets。
   
   📋 **配置清单**：[docs/WIF-CHECKLIST.md](docs/WIF-CHECKLIST.md)

2. **上传环境变量**
   ```bash
   make push-env
   ```

3. **推送代码触发部署**
   ```bash
   git add .
   git commit -m "Update configuration"
   git push origin main
   ```

#### 查看部署进度
- 在 GitHub 仓库的 **Actions** 标签页查看部署状态
- 首次部署会自动运行 `deploy.sh` 申请证书
- 后续更新会进行零停机重启

📖 **详细指南**：
- [WIF 配置指南](docs/WIF-SETUP-GUIDE.md)（完整说明）
- [WIF 快速清单](docs/WIF-CHECKLIST.md)（快速参考）

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
make uuid

# 生成 Reality 密钥对
make reality-key

# 生成随机密码
make password

# 生成 Short ID
make short-id
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
