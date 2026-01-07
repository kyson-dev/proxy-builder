# S-UI 代理服务部署指南

## 🎯 项目特点

这是一个基于 **S-UI** 的代理服务部署方案，具有以下特点：

- ✅ **Web 管理面板** - 通过浏览器管理所有配置
- ✅ **HTTPS 加密** - Caddy 自动申请和续期 SSL 证书
- ✅ **订阅服务** - 内置用户订阅功能（HTTPS 加密）
- ✅ **多协议支持** - VLESS、Hysteria2、Trojan、Shadowsocks 等
- ✅ **流量统计** - 用户流量监控和限额管理
- ✅ **一键部署** - Docker Compose 快速启动

## 📦 支持的协议

S-UI 基于 Sing-Box，支持所有主流协议：

- **V2Ray 系**: VLESS, VMess, Trojan, Shadowsocks
- **高性能协议**: Hysteria, Hysteria2, TUIC
- **特殊协议**: ShadowTLS, Naive
- **Reality 支持**: VLESS + Reality 无需证书

## 🚀 快速开始

### 1. 服务器准备

确保服务器满足以下条件：
- Linux 系统 (Ubuntu/Debian/CentOS)
- 已配置域名解析（指向服务器 IP）
- 开放必要端口 (80, 443, 2095, 2096)

### 2. 配置环境变量

根据部署环境选择对应的配置文件：

**Production 环境：**
```bash
# 复制 production 模板
cp .env.production.example .env.production

# 编辑配置
nano .env.production
```

**Development 环境：**
```bash
# 复制 development 模板
cp .env.development.example .env.development

# 编辑配置
nano .env.development
```

在配置文件中设置你的域名：
```bash
PANEL_DOMAIN=panel.example.com  # production
# 或
PANEL_DOMAIN=dev-panel.example.com  # development
```

### 3. 一键部署

```bash
chmod +x deploy.sh
./deploy.sh
```

脚本会自动：
- ✅ 加载 `.env` 配置
- ✅ 启用 BBR 加速
- ✅ 安装 Docker
- ✅ 生成自签名证书（用于 Hysteria2）
- ✅ 启动 S-UI 和 Caddy 服务
- ✅ 自动申请 Let's Encrypt SSL 证书

### 4. 访问管理面板

部署完成后，访问：

```
https://panel.example.com:2095/app/
```

**默认登录信息**：
- 用户名: `admin`
- 密码: `admin`

> ⚠️ **安全警告**: 首次登录后请立即修改默认密码！

### 5. 配置代理入口

在 S-UI 面板中配置 Inbound：

1. **VLESS Reality** (推荐端口: 443)
   - 无需证书，最安全的方案
   - 使用 `make reality-key` 生成密钥对

2. **Hysteria2** (推荐端口: 443)
   - 高性能 UDP 协议
   - 使用预生成的自签名证书 (`~/data/s-ui/cert/`)

## 🤖 GitHub Actions 自动部署

### 配置步骤

1. **创建环境配置文件**
   ```bash
   # Production 环境
   cp .env.production.example .env.production
   nano .env.production
   
   # Development 环境
   cp .env.development.example .env.development
   nano .env.development
   ```

2. **上传环境变量到 GitHub**
   ```bash
   # 确保已安装并登录 GitHub CLI
   gh auth login
   
   # 运行推送脚本（会提示选择环境）
   make upload-env
   ```
   
   脚本会：
   - ✅ 根据当前 git 分支自动推荐环境
   - ✅ 读取对应的 `.env.{environment}` 文件
   - ✅ 逐个上传环境变量到 GitHub Secrets
   - ✅ 显示详细的上传统计

3. **推送代码触发部署**
   ```bash
   git push origin main      # 部署到 production
   git push origin dev       # 部署到 development
   ```

### 环境说明

| 分支 | 环境 | 配置文件 | 自动部署 |
|------|------|---------|---------|
| `main` | production | `.env.production` | ✅ |
| `dev` | development | `.env.development` | ✅ |

### 工作流程

```
本地开发
  ↓
编辑 .env.{environment}
  ↓
make upload-env  ← 自动推送到 GitHub Secrets
  ↓
git push
  ↓
GitHub Actions 自动部署
  ↓
服务器自动配置 Caddy + S-UI
```

## 📊 端口说明

| 端口 | 协议 | 用途 | 加密 |
|------|------|------|------|
| 80 | TCP | HTTP (ACME 验证) | - |
| 443 | TCP/UDP | 代理节点流量 | 协议加密 |
| 2095 | TCP | S-UI Web 管理面板 | HTTPS (Caddy) |
| 2096 | TCP | 订阅服务 | HTTPS (Caddy) |

**防火墙设置**：

```bash
# Ubuntu/Debian
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 443/udp
sudo ufw allow 2095/tcp
sudo ufw allow 2096/tcp

# CentOS/RHEL
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --permanent --add-port=443/udp
sudo firewall-cmd --permanent --add-port=2095/tcp
sudo firewall-cmd --permanent --add-port=2096/tcp
sudo firewall-cmd --reload
```

## 🔧 常用命令

```bash
# 查看服务状态
docker compose ps

# 查看 S-UI 日志
docker logs -f s-ui

# 重启服务
docker compose restart

# 停止服务
docker compose down

# 更新 S-UI
docker compose pull
docker compose up -d
```

## 🛠️ Makefile 工具

```bash
# 生成 VLESS UUID
make uuid

# 生成 Reality 密钥对
make reality-key

# 生成随机密码
make password

# 生成自签名证书
make generate-cert

# 检查证书有效期
make check-cert
```

## 📁 项目结构

```
proxy-builder/
├── docker-compose.yml    # S-UI 服务定义
├── deploy.sh             # 一键部署脚本
├── Makefile              # 工具命令
├── s-ui/
│   ├── db/               # S-UI 数据库 (运行时生成)
│   └── cert/             # 自签名证书目录
└── scripts/
    ├── deploy/           # 部署子模块
    └── lib/              # 通用函数库
```

## 🔐 安全建议

1. **修改默认密码** - 首次登录后立即修改
2. **启用 HTTPS** - 在面板设置中配置 SSL
3. **定期更新** - 保持 S-UI 版本最新
4. **监控流量** - 定期检查异常流量

## ❓ 常见问题

### Q: 无法访问管理面板？

检查：
1. 防火墙是否开放 2095 端口
2. Docker 服务是否正常运行 (`docker compose ps`)
3. 查看日志 (`docker logs s-ui`)

### Q: Hysteria2 使用自签名证书？

在 S-UI 中配置 Hysteria2 时：
1. 证书路径: `/app/cert/cert.pem`
2. 密钥路径: `/app/cert/key.pem`
3. 客户端需设置 `insecure: true`

### Q: 如何备份数据？

S-UI 数据存储在 `s-ui/db/` 目录，备份此目录即可。

## 📚 相关资源

- [S-UI 官方仓库](https://github.com/alireza0/s-ui)
- [S-UI API 文档](https://github.com/alireza0/s-ui/wiki/API-Documentation)
- [Sing-box 官方文档](https://sing-box.sagernet.org/)

---

**License**: MIT  
**维护者**: Kyson
