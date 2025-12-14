# 简化版本更新日志

## ✨ 主要改进

### 1. 移除了不必要的组件

- ❌ **Nginx** - 不再需要（无需证书申请）
- ❌ **Certbot** - 不再需要（不使用 Let's Encrypt）
- ❌ **TUIC** - 移除（简化配置）
- ❌ **域名依赖** - 完全移除

### 2. 保留的协议

- ✅ **VLESS Reality** (端口 8443)
  - 无需任何证书
  - 伪装成 Microsoft 官网
  - 最安全的无证书方案

- ✅ **Hysteria2** (端口 9443)
  - 使用自动生成的自签名证书
  - 高性能 UDP 协议
  - 100 年有效期

### 3. 智能证书管理

#### deploy.sh 增强功能

```bash
# 自动检测和生成证书
- 检查证书是否存在
- 验证证书有效性
- 自动生成（如果不存在或过期）
- 显示证书信息（CN、过期时间）
- 设置正确的文件权限
- 双重备用方案（RSA/EC）
```

#### Makefile 新增命令

```bash
make generate-cert  # 生成新的自签名证书
make check-cert     # 检查证书信息和有效性
```

### 4. 部署流程简化

**之前的流程：**
```
1. 配置域名和 DNS
2. 等待 DNS 生效
3. 启动 Nginx
4. 申请 Let's Encrypt 证书
5. 配置 Nginx HTTPS
6. 启动代理服务
```

**现在的流程：**
```
1. 生成密钥配置
2. 运行 ./deploy.sh（自动生成证书）
3. 完成！
```

### 5. 配置文件变更

#### .env 文件简化

**移除的变量：**
- `DOMAIN` - 不再需要域名
- `EMAIL` - 不再需要邮箱
- `TUIC_UUID` - 移除 TUIC 协议
- `TUIC_PASSWORD` - 移除 TUIC 协议

**保留的变量：**
```bash
VLESS_UUID=...
REALITY_PRIVATE_KEY=...
REALITY_PUBLIC_KEY=...
REALITY_SHORT_ID=...
H2_PASSWORD=...
```

#### docker-compose.yml 简化

**移除的服务：**
- nginx
- certbot

**保留的服务：**
- sing-box（已简化配置）

### 6. 自签名证书特性

#### 证书规格

```
算法: RSA 2048（主）或 EC P-256（备用）
CN: bing.com
有效期: 100 年（36500 天）
文件位置: ./sing-box/certs/
  - cert.pem (644 权限)
  - key.pem (600 权限)
```

#### 自动管理

- ✅ 首次部署自动生成
- ✅ 每次部署检查有效性
- ✅ 过期自动重新生成
- ✅ 显示证书详细信息
- ✅ 错误处理和备用方案

### 7. 客户端配置变化

#### VLESS Reality
**无变化** - 仍然使用相同的配置

#### Hysteria2
**重要变化：**
```yaml
# 必须添加此配置
tls:
  insecure: true  # 跳过证书验证

# 或者导入证书
tls:
  ca: /path/to/cert.pem
```

### 8. 新增文档

```
docs/
├── QUICKSTART.md                      # 快速开始指南
└── client-examples/                   # 客户端配置示例
    ├── vless-reality.md               # VLESS Reality 详细配置
    └── hysteria2.md                   # Hysteria2 详细配置
```

## 📊 对比总结

| 项目 | 完整版 | 简化版 |
|------|--------|--------|
| 域名要求 | ✅ 必需 | ❌ 不需要 |
| DNS 配置 | ✅ 必需 | ❌ 不需要 |
| Let's Encrypt | ✅ 需要 | ❌ 不需要 |
| Nginx | ✅ 需要 | ❌ 不需要 |
| Certbot | ✅ 需要 | ❌ 不需要 |
| 部署时间 | ~5-10 分钟 | ~2 分钟 |
| 配置复杂度 | 中等 | 简单 |
| VLESS Reality | ✅ | ✅ |
| Hysteria2 | ✅ 正式证书 | ✅ 自签名 |
| TUIC | ✅ | ❌ |
| 证书自动续期 | ✅ | ⚠️ 100年有效 |

## 🚀 使用建议

### 适用场景

**简化版适合：**
- ✅ 个人使用
- ✅ 快速测试
- ✅ 无法获取域名的情况
- ✅ 需要快速部署
- ✅ 学习和实验

**完整版适合：**
- ✅ 生产环境
- ✅ 需要正式证书
- ✅ 多协议支持
- ✅ 需要 HTTPS 伪装

### 迁移指南

**从完整版迁移到简化版：**

```bash
# 1. 备份现有配置
cp .env .env.backup
cp docker-compose.yml docker-compose.yml.backup

# 2. 更新配置文件
# 移除 DOMAIN, EMAIL, TUIC_* 变量

# 3. 停止旧服务
docker compose down

# 4. 使用新配置部署
./deploy.sh
```

**从简化版升级到完整版：**

```bash
# 1. 添加域名配置
echo "DOMAIN=your-domain.com" >> .env
echo "EMAIL=your-email@example.com" >> .env

# 2. 生成 TUIC 配置
echo "TUIC_UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')" >> .env
echo "TUIC_PASSWORD=$(openssl rand -base64 32)" >> .env

# 3. 使用完整版配置
# 替换 docker-compose.yml 和相关配置
```

## 🔧 维护指南

### 证书管理

```bash
# 查看证书信息
make check-cert

# 手动重新生成证书
make generate-cert

# 部署时自动检查
./deploy.sh  # 会自动检查和生成
```

### 日常维护

```bash
# 查看服务状态
docker compose ps

# 查看日志
docker logs -f sing-box

# 重启服务
docker compose restart

# 更新到最新版本
docker compose pull
docker compose up -d
```

### 故障排除

**问题 1: 证书生成失败**
```bash
# 检查 OpenSSL
which openssl
openssl version

# 手动测试生成
openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout test-key.pem -out test-cert.pem \
  -subj "/CN=test" -days 365
```

**问题 2: Hysteria2 连接失败**
```bash
# 确认客户端设置
tls:
  insecure: true  # 必须设置

# 检查防火墙
sudo ufw allow 9443/udp

# 查看日志
docker logs sing-box | grep hysteria
```

**问题 3: VLESS Reality 连接失败**
```bash
# 检查时间同步
date
# 时间差不能超过 90 秒

# 检查配置
# 确保使用 PUBLIC_KEY 而非 PRIVATE_KEY
```

## 📚 相关文档

- [README.md](../README.md) - 完整说明
- [QUICKSTART.md](./QUICKSTART.md) - 快速开始
- [客户端配置示例](./client-examples/) - 详细配置

## 🎯 下一步计划

可能的增强功能（未来版本）：
- [ ] 支持自定义证书 CN
- [ ] 证书过期提醒
- [ ] 一键客户端配置导出
- [ ] Web UI 管理界面
- [ ] 流量统计功能
- [ ] 自动备份配置

---

**版本**: 2.0 (简化版)  
**更新日期**: 2025-12-14  
**维护者**: Kyson
