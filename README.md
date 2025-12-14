# 简化代理服务部署指南

## 🎯 项目特点

这是一个**极简版本**的代理服务配置，具有以下特点：

- ✅ **无需域名** - 不依赖任何域名和DNS配置
- ✅ **无需Let's Encrypt** - 不需要申请和维护SSL证书
- ✅ **自签名证书** - Hysteria2使用自动生成的自签名证书
- ✅ **简单快速** - 一键部署，几分钟内完成

## 📦 支持的协议

1. **VLESS + Reality** (端口 8443)
   - 无需任何证书
   - 伪装成 Microsoft 官网
   - 最安全的无证书方案

2. **Hysteria2** (端口 9443)
   - 使用自签名证书
   - 高性能UDP协议
   - 客户端需要启用 `insecure` 选项

## 🚀 快速开始

### 1. 生成密钥

使用项目提供的脚本生成所需的UUID和密钥：

```bash
# 生成 VLESS UUID
uuidgen | tr '[:upper:]' '[:lower:]'

# 生成 Reality 密钥对
docker run --rm ghcr.io/sagernet/sing-box sing-box generate reality-keypair

# 生成 Reality Short ID
openssl rand -hex 8

# 生成 Hysteria2 密码
openssl rand -base64 32
```

### 2. 配置环境变量

复制环境变量示例文件：

```bash
cp .env.development.example .env.development
# 或生产环境
cp .env.production.example .env.production
```

然后编辑 `.env.development`，填入刚才生成的值：

```bash
# VLESS + Reality
VLESS_UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
REALITY_PRIVATE_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
REALITY_PUBLIC_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
REALITY_SHORT_ID=xxxxxxxxxxxxxxxx

# Hysteria2
H2_PASSWORD=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

### 3. 创建符号链接

根据你的环境创建 `.env` 符号链接：

```bash
# 开发环境
ln -sf .env.development .env

# 或生产环境
ln -sf .env.production .env
```

### 4. 部署服务

运行部署脚本：

```bash
chmod +x deploy.sh
./deploy.sh
```

脚本会自动：
- ✅ 检查环境变量
- ✅ 生成 Hysteria2 自签名证书
- ✅ 启动 Sing-box 服务

## 📱 客户端配置

### VLESS Reality 配置

```json
{
  "protocol": "vless",
  "settings": {
    "vnext": [{
      "address": "YOUR_SERVER_IP",
      "port": 8443,
      "users": [{
        "id": "YOUR_VLESS_UUID",
        "flow": "xtls-rprx-vision",
        "encryption": "none"
      }]
    }]
  },
  "streamSettings": {
    "network": "tcp",
    "security": "reality",
    "realitySettings": {
      "serverName": "www.microsoft.com",
      "publicKey": "YOUR_REALITY_PUBLIC_KEY",
      "shortId": "YOUR_REALITY_SHORT_ID",
      "fingerprint": "chrome"
    }
  }
}
```

### Hysteria2 配置

```yaml
server: YOUR_SERVER_IP:9443
auth: YOUR_H2_PASSWORD
tls:
  insecure: true  # ⚠️ 必须设置为 true（使用自签名证书）
bandwidth:
  up: 100 mbps
  down: 500 mbps
```

**重要提示**：Hysteria2 使用自签名证书，必须在客户端设置 `insecure: true`。

## 🔧 常用命令

```bash
# 查看服务状态
docker compose ps

# 查看 Sing-box 日志
docker logs -f sing-box

# 重启服务
docker compose restart

# 停止服务
docker compose down

# 更新并重启
docker compose pull
docker compose up -d
```

## 📊 端口使用

| 协议 | 端口 | 用途 |
|------|------|------|
| VLESS Reality | 8443 | TCP 代理（无需证书） |
| Hysteria2 | 9443 | UDP 代理（自签名证书） |

**防火墙设置**：确保开放以下端口

```bash
# Ubuntu/Debian
sudo ufw allow 8443/tcp
sudo ufw allow 9443/udp

# CentOS/RHEL
sudo firewall-cmd --permanent --add-port=8443/tcp
sudo firewall-cmd --permanent --add-port=9443/udp
sudo firewall-cmd --reload
```

## 🔐 安全建议

1. **定期更换密码** - 建议每月更换一次密码和UUID
2. **限制访问源** - 如果可能，限制特定IP访问
3. **监控流量** - 定期检查异常流量
4. **备份配置** - 保存好环境变量文件

## ❓ 常见问题

### Q: Hysteria2 连接失败？

**A:** 检查以下几点：
1. 客户端是否设置了 `insecure: true`
2. 服务器防火墙是否开放 UDP 9443 端口
3. 密码是否正确

### Q: VLESS Reality 无法连接？

**A:** 检查：
1. Public Key 是否正确（注意不是 Private Key）
2. Short ID 是否匹配
3. 服务器防火墙是否开放 TCP 8443 端口

### Q: 如何重新生成证书？

**A:** 删除旧证书后重新部署：

```bash
rm -rf sing-box/certs/*
./deploy.sh
```

## 📝 项目结构

```
.
├── .env.development.example    # 开发环境变量示例
├── .env.production.example     # 生产环境变量示例
├── deploy.sh                   # 部署脚本
├── docker-compose.yml          # Docker 编排文件
├── sing-box/
│   ├── config.json.template   # Sing-box 配置模板
│   ├── entrypoint.sh          # 容器启动脚本
│   └── certs/                 # 自签名证书目录（自动生成）
└── README.md                   # 本文件
```

## 🆚 与完整版本的区别

| 功能 | 简化版 | 完整版 |
|------|--------|--------|
| 域名要求 | ❌ 不需要 | ✅ 需要 |
| Let's Encrypt | ❌ 不需要 | ✅ 需要 |
| Nginx | ❌ 不需要 | ✅ 需要 |
| VLESS Reality | ✅ 支持 | ✅ 支持 |
| Hysteria2 | ✅ 自签名 | ✅ 正式证书 |
| TUIC | ❌ 移除 | ✅ 支持 |
| 部署时间 | < 2分钟 | > 5分钟 |

## 📚 相关资源

- [Sing-box 官方文档](https://sing-box.sagernet.org/)
- [VLESS Protocol](https://github.com/XTLS/VLESS)
- [Hysteria2 文档](https://v2.hysteria.network/)
- [Reality 协议说明](https://github.com/XTLS/REALITY)

---

**License**: MIT  
**维护者**: Kyson
