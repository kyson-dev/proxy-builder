# S-UI 代理服务部署指南

## 🎯 项目特点

这是一个基于 **S-UI** 的代理服务部署方案，具有以下特点：

- ✅ **Web 管理面板** - 通过浏览器管理所有配置
- ✅ **无需域名** - 不依赖任何域名和 DNS 配置
- ✅ **订阅服务** - 内置用户订阅功能
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
- 开放必要端口 (2095, 2096, 8443, 9443)

### 2. 一键部署

```bash
chmod +x deploy.sh
./deploy.sh
```

脚本会自动：
- ✅ 启用 BBR 加速
- ✅ 安装 Docker
- ✅ 生成 Hysteria2 自签名证书
- ✅ 启动 S-UI 服务

### 3. 访问管理面板

部署完成后，访问：

```
http://<服务器IP>:2095/app/
```

**默认登录信息**：
- 用户名: `admin`
- 密码: `admin`

> ⚠️ **安全警告**: 首次登录后请立即修改默认密码！

### 4. 配置代理入口

在 S-UI 面板中配置 Inbound：

1. **VLESS Reality** (推荐端口: 8443)
   - 无需证书，最安全的方案
   - 使用 `make reality-key` 生成密钥对

2. **Hysteria2** (推荐端口: 9443)
   - 高性能 UDP 协议
   - 使用预生成的自签名证书 (`s-ui/cert/`)

## 📊 端口说明

| 端口 | 协议 | 用途 |
|------|------|------|
| 2095 | TCP | S-UI Web 管理面板 |
| 2096 | TCP | 订阅服务 |
| 8443 | TCP | VLESS Reality (需在 UI 配置) |
| 9443 | UDP | Hysteria2 (需在 UI 配置) |

**防火墙设置**：

```bash
# Ubuntu/Debian
sudo ufw allow 2095/tcp
sudo ufw allow 2096/tcp
sudo ufw allow 8443/tcp
sudo ufw allow 9443/udp

# CentOS/RHEL
sudo firewall-cmd --permanent --add-port=2095/tcp
sudo firewall-cmd --permanent --add-port=2096/tcp
sudo firewall-cmd --permanent --add-port=8443/tcp
sudo firewall-cmd --permanent --add-port=9443/udp
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
