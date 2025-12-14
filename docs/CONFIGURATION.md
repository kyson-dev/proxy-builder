# 配置说明

## 快速开始

1. **复制配置模板**
   ```bash
   cp vars.production.example.json vars.production.json
   ```

2. **生成必要的密钥**
   ```bash
   # 生成 UUID（用于 VLESS 用户）
   make uuid
   
   # 生成密码（用于 Hysteria2 用户）
   make password
   
   # 生成 Reality 密钥对
   make reality-key
   
   # 生成 Reality Short ID
   make short-id
   ```

3. **编辑配置文件**
   ```bash
   vim vars.production.json
   ```

4. **上传到 GitHub Secret**
   ```bash
   make push-config-prod
   ```

## 配置项说明

### 端口配置

```json
"ports": {
  "vless": 443,
  "hysteria2": 443
}
```

**重要说明**：
- VLESS Reality 使用 **TCP 443**
- Hysteria2 使用 **UDP 443**
- 两者可以共用同一端口，因为传输层协议不同
- 使用 443 端口更隐蔽，流量看起来像正常 HTTPS

**防火墙配置**：
确保 GCP 防火墙同时开放 TCP 和 UDP 443：
```bash
# TCP 443（VLESS）
gcloud compute firewall-rules create allow-https-tcp \
  --allow tcp:443 \
  --source-ranges 0.0.0.0/0

# UDP 443（Hysteria2）
gcloud compute firewall-rules create allow-https-udp \
  --allow udp:443 \
  --source-ranges 0.0.0.0/0
```

### 用户配置

#### VLESS 用户
```json
"vless_users": [
  {"uuid": "uuid-1", "flow": "xtls-rprx-vision"},
  {"uuid": "uuid-2", "flow": "xtls-rprx-vision"}
]
```
- 支持多用户
- 每个用户需要唯一的 UUID
- `flow` 固定为 `xtls-rprx-vision`

#### Hysteria2 用户
```json
"h2_users": [
  {"password": "password-1"},
  {"password": "password-2"}
]
```
- 支持多用户
- 每个用户使用独立密码

### Reality 配置

```json
"reality": {
  "private_key": "your-private-key",
  "public_key": "your-public-key",
  "short_id": "your-short-id"
}
```

- `private_key` 和 `public_key` 必须配对
- 使用 `make reality-key` 生成密钥对
- `short_id` 用于标识，使用 `make short-id` 生成

## 多环境管理

### 生产环境
```bash
cp vars.production.example.json vars.production.json
# 编辑配置...
make push-config-prod
```

### 开发环境
```bash
cp vars.development.example.json vars.development.json
# 编辑配置...
make push-config-dev
```

## 注意事项

1. **不要提交敏感配置**：`vars.production.json` 和 `vars.development.json` 已在 `.gitignore` 中
2. **定期轮换密钥**：建议定期更新 UUID 和密码
3. **备份配置**：重要配置请妥善备份
4. **端口冲突**：如果修改端口，确保不与其他服务冲突
