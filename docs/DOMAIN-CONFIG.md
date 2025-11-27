# 域名配置指南

## 🔄 更换域名需要修改的文件

如果要从 `kyson.site` 换成其他域名（如 `example.com`），需要修改以下文件：

### 1. **核心配置文件**（必须修改）

#### ✏️ `nginx/nginx.conf`
```nginx
server_name kyson.site;  # 改为新域名
```

#### ✏️ `sing-box/config.json`
修改证书路径（2处）：
```json
"certificate_path": "/etc/letsencrypt/live/kyson.site/fullchain.pem",
"key_path": "/etc/letsencrypt/live/kyson.site/privkey.pem"
```

#### ✏️ `deploy.sh`
修改域名检查和证书申请（4处）：
```bash
if ! host kyson.site > /dev/null 2>&1; then
    echo "⚠️  警告: kyson.site DNS 解析失败"
    ...
fi

if [ ! -d "certs/live/kyson.site" ]; then
    ...
    -d kyson.site \
    --email admin@kyson.site \
    ...
fi
```

### 2. **文档文件**（可选修改）

这些文件只是文档说明，不影响服务运行：
- `README.md` - 多处示例
- `webroot/README.md` - 示例说明
- `docs/WEBROOT-EXPLAINED.md` - 示例说明

---

## 📝 快速替换脚本

使用以下命令一键替换所有域名：

```bash
# 定义新旧域名
OLD_DOMAIN="kyson.site"
NEW_DOMAIN="example.com"  # 改为你的新域名

# 替换所有文件中的域名
find . -type f \( -name "*.conf" -o -name "*.json" -o -name "*.sh" -o -name "*.md" \) \
  -not -path "./.git/*" \
  -exec sed -i '' "s/$OLD_DOMAIN/$NEW_DOMAIN/g" {} +

echo "✅ 域名已从 $OLD_DOMAIN 替换为 $NEW_DOMAIN"
echo "⚠️  请检查以下文件确认修改正确："
echo "   - nginx/nginx.conf"
echo "   - sing-box/config.json"
echo "   - deploy.sh"
```

---

## 🔐 关于证书和子域名

### ❌ 当前配置：不包含子域名

使用 `certbot certonly -d kyson.site` 申请的证书**只包含**：
- ✅ `kyson.site`
- ❌ `www.kyson.site`（不包含）
- ❌ `api.kyson.site`（不包含）
- ❌ `*.kyson.site`（不包含）

### ✅ 如何申请包含子域名的证书？

#### 方法 1：指定多个域名
```bash
docker compose run --rm certbot certbot certonly \
  --webroot -w /var/www/html \
  -d kyson.site \
  -d www.kyson.site \
  -d api.kyson.site \
  --agree-tos \
  --email admin@kyson.site \
  --non-interactive
```

**注意**：
- 每个子域名都需要单独指定
- 所有域名的 DNS 都必须指向服务器
- 证书会包含所有指定的域名

#### 方法 2：通配符证书（推荐）
```bash
# 需要使用 DNS-01 验证（不能用 webroot）
docker compose run --rm certbot certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials /path/to/cloudflare.ini \
  -d kyson.site \
  -d "*.kyson.site" \
  --agree-tos \
  --email admin@kyson.site \
  --non-interactive
```

**优点**：
- ✅ 一次申请，所有子域名都支持
- ✅ `*.kyson.site` 匹配所有子域名

**缺点**：
- ❌ 需要 DNS 提供商 API 支持（如 Cloudflare）
- ❌ 配置稍复杂

---

## 🎯 当前证书覆盖范围

### 查看证书包含的域名
```bash
docker compose exec certbot certbot certificates
```

### 示例输出
```
Certificate Name: kyson.site
  Domains: kyson.site          # ← 只有这一个域名
  Expiry Date: 2025-02-25
  Certificate Path: /etc/letsencrypt/live/kyson.site/fullchain.pem
  Private Key Path: /etc/letsencrypt/live/kyson.site/privkey.pem
```

---

## 💡 推荐配置

### 场景 1：只需要主域名
```bash
# 当前配置已满足
-d kyson.site
```

### 场景 2：需要 www 子域名
```bash
# 修改 deploy.sh
-d kyson.site \
-d www.kyson.site
```

### 场景 3：需要多个子域名
```bash
# 修改 deploy.sh
-d kyson.site \
-d www.kyson.site \
-d api.kyson.site \
-d proxy.kyson.site
```

### 场景 4：需要所有子域名（通配符）
```bash
# 需要改用 DNS-01 验证
# 参考 Certbot DNS 插件文档
```

---

## ⚠️ 重要提醒

1. **DNS 必须先配置**：所有要申请证书的域名都必须先配置 DNS A 记录
2. **证书不会自动包含子域名**：必须显式指定
3. **通配符证书需要 DNS API**：不能使用 webroot 模式
4. **Let's Encrypt 限制**：每周最多申请 50 个证书

---

## 🔄 修改域名后的步骤

1. **修改配置文件**（使用上面的脚本或手动修改）
2. **配置新域名的 DNS**
3. **删除旧证书**：`rm -rf certs/live/kyson.site`
4. **重新部署**：`./deploy.sh`
