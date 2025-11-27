# Certbot Webroot 模式说明

## 为什么 Certbot 需要挂载 webroot？

### HTTP-01 验证流程

当 Certbot 使用 webroot 模式申请证书时：

```
1. Certbot 创建验证文件
   └─> 写入到 /var/www/html/.well-known/acme-challenge/RANDOM_TOKEN

2. Let's Encrypt 服务器访问
   └─> GET http://kyson.site/.well-known/acme-challenge/RANDOM_TOKEN

3. Nginx 提供文件
   └─> 从 /var/www/html/.well-known/acme-challenge/RANDOM_TOKEN 读取并返回

4. 验证成功
   └─> Let's Encrypt 签发证书
```

### 为什么需要共享目录？

**两个容器需要访问同一个目录**：

| 容器 | 操作 | 路径 |
|------|------|------|
| **Certbot** | 写入验证文件 | `/var/www/html/.well-known/acme-challenge/` |
| **Nginx** | 读取并提供文件 | `/var/www/html/.well-known/acme-challenge/` |

通过 Docker volume 挂载 `./webroot:/var/www/html`，两个容器可以共享同一个目录。

### Docker Compose 配置

```yaml
nginx:
  volumes:
    - ./webroot:/var/www/html  # Nginx 读取文件

certbot:
  volumes:
    - ./webroot:/var/www/html  # Certbot 写入文件
```

### Nginx 配置

```nginx
location /.well-known/acme-challenge/ {
    root /var/www/html;  # 指向挂载的 webroot 目录
}
```

## 对比其他模式

### Standalone 模式（不推荐）
```bash
certbot certonly --standalone
```
- ❌ Certbot 启动自己的 HTTP 服务器占用 80 端口
- ❌ 需要停止 Nginx 才能申请/续期证书
- ❌ 续期时服务中断

### Webroot 模式（当前使用）
```bash
certbot certonly --webroot -w /var/www/html
```
- ✅ 不需要停止任何服务
- ✅ Nginx 持续运行
- ✅ 续期无感知

### DNS 模式（高级）
```bash
certbot certonly --dns-cloudflare
```
- ✅ 不需要开放 80 端口
- ✅ 支持通配符证书
- ❌ 需要 DNS API 支持

## 总结

**webroot 目录是 Nginx 和 Certbot 之间的"桥梁"**：
- Certbot 在这里放置验证文件
- Nginx 从这里读取并提供给 Let's Encrypt
- 两个容器通过共享这个目录实现协作
