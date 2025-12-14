# Nginx 分层配置架构

## 🎯 设计目标

简化 `deploy.sh` 的证书管理逻辑，避免动态修改 Nginx 配置文件。

---

## 📐 架构设计

### 文件结构

```
nginx/
├── nginx.conf              # 主配置文件（使用 include 指令）
└── conf.d/
    ├── certbot.conf       # 证书申请配置（HTTP-01 Challenge）
    └── (future) proxy.conf # 未来可扩展的代理配置
```

### 配置分层

#### 1. `nginx.conf` - 主配置

```nginx
events {
    worker_connections 1024;
}

http {
    # 包含所有模块化配置
    include /etc/nginx/conf.d/*.conf;
}
```

**作用：**
- 定义全局配置
- 通过 `include` 加载所有子配置
- 保持简洁，不包含具体业务逻辑

#### 2. `conf.d/certbot.conf` - 证书申请配置

```nginx
server {
    listen 80;
    server_name kyson.site;

    # Certbot webroot 验证路径
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    # 其他请求返回简单页面
    location / {
        root /var/www/html;
        index index.html;
    }
}
```

**作用：**
- 专门处理 Let's Encrypt 的 HTTP-01 验证
- 始终加载，Nginx 可以一直运行
- 支持 Certbot 的自动续期

---

## 🔄 工作流程

### 旧方案（复杂）

```
1. 检查证书是否存在
2. 如果不存在：
   a. 备份 nginx.conf
   b. 动态生成临时配置
   c. 启动 Nginx
   d. 申请证书
   e. 恢复原始配置
   f. 停止 Nginx
3. 启动所有服务
```

**问题：**
- ❌ 需要动态修改配置文件
- ❌ 需要备份和恢复逻辑
- ❌ 需要 cleanup 函数处理中断
- ❌ 代码复杂，容易出错

### 新方案（简洁）

```
1. 检查证书是否存在
2. 如果不存在：
   a. 启动 Nginx（自动加载 certbot.conf）
   b. 申请证书
   c. 完成
3. 如果已存在：
   a. 确保 Nginx 运行（用于自动续期）
4. 启动所有服务
```

**优势：**
- ✅ 不需要修改配置文件
- ✅ 不需要备份恢复
- ✅ 不需要 cleanup 函数
- ✅ 代码简洁清晰
- ✅ Nginx 可以一直运行

---

## 📊 对比

| 方面 | 旧方案 | 新方案 |
|------|--------|--------|
| **配置文件修改** | 动态生成 | 静态加载 |
| **备份恢复** | 需要 | 不需要 |
| **Cleanup 逻辑** | 需要 | 不需要 |
| **代码行数** | ~90 行 | ~30 行 |
| **Nginx 状态** | 启动→停止→启动 | 一直运行 |
| **可维护性** | 低 | 高 |
| **扩展性** | 差 | 好 |

---

## 🚀 扩展性

### 未来可以添加更多配置

```
nginx/conf.d/
├── certbot.conf       # 证书申请
├── proxy.conf         # 反向代理（如果需要）
├── security.conf      # 安全配置
└── logging.conf       # 日志配置
```

### 示例：添加反向代理

创建 `nginx/conf.d/proxy.conf`：

```nginx
server {
    listen 443 ssl http2;
    server_name kyson.site;

    ssl_certificate /etc/letsencrypt/live/kyson.site/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/kyson.site/privkey.pem;

    location / {
        proxy_pass http://backend:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

**无需修改主配置**，只需添加新文件即可。

---

## 🛠️ Docker Compose 配置

```yaml
nginx:
  image: nginx:alpine
  volumes:
    - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    - ./nginx/conf.d:/etc/nginx/conf.d:ro  # 挂载整个目录
    - ./webroot:/var/www/html
```

**关键点：**
- 挂载 `conf.d` 整个目录
- 使用 `:ro` 只读模式（安全）
- Nginx 自动加载所有 `.conf` 文件

---

## ✅ 优势总结

1. **简化部署脚本**
   - 减少 60% 的代码
   - 消除复杂的备份恢复逻辑

2. **提高可靠性**
   - 无需动态修改配置
   - 减少出错可能

3. **增强可维护性**
   - 配置模块化
   - 职责清晰

4. **支持扩展**
   - 添加新功能只需新增配置文件
   - 不影响现有配置

5. **符合最佳实践**
   - Nginx 官方推荐的配置方式
   - 生产环境常用模式

---

## 📚 相关文档

- [Nginx Include 指令文档](http://nginx.org/en/docs/ngx_core_module.html#include)
- [Let's Encrypt Webroot 模式](https://letsencrypt.org/docs/challenge-types/#http-01-challenge)
- [项目架构文档](./ARCHITECTURE.md)
