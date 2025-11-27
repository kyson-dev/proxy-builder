# Webroot 目录说明

这个目录用于 Let's Encrypt 的 HTTP-01 验证。

## 工作原理

1. **Nginx** 将 `/.well-known/acme-challenge/` 路径映射到这个目录
2. **Certbot** 在申请/续期证书时，会在这里创建验证文件
3. **Let's Encrypt** 通过 HTTP 访问这些文件来验证域名所有权

## 为什么 Certbot 需要挂载这个目录？

Certbot 使用 **webroot 模式**申请证书：
- 申请证书时：Certbot 在 `/var/www/html/.well-known/acme-challenge/` 创建临时验证文件
- Let's Encrypt 访问：`http://kyson.site/.well-known/acme-challenge/TOKEN`
- Nginx 提供这个文件
- 验证成功后，Certbot 删除文件并签发证书

**两个容器都需要访问同一个目录**：
- Nginx 读取文件（提供 HTTP 服务）
- Certbot 写入文件（创建验证文件）

## 目录内容

正常情况下这个目录是空的，只有在证书申请/续期时才会临时出现 `.well-known/` 目录。
