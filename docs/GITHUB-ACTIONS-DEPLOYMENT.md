# GitHub Actions 部署流程说明

## 📋 部署流程概览

```
┌─────────────────────────────────────────────────────────────┐
│                   GitHub Actions 触发                        │
│                  (手动 workflow_dispatch)                    │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  Step 1: 选择环境                                            │
│  • main 分支 → production 环境                               │
│  • 其他分支 → development 环境                               │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  Step 2: 认证到 GCP (Workload Identity Federation)          │
│  • 使用 WIF 无密钥认证                                       │
│  • 获取临时访问令牌                                          │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  Step 3: 配置 SSH                                            │
│  • gcloud compute config-ssh                                │
│  • 构建 VM 主机名: name.zone.project                        │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  Step 4: 准备远程目录                                        │
│  • 检测远程用户 home 目录                                    │
│  • 创建 ~/app 目录                                           │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  Step 5: 同步文件到服务器 (rsync)                            │
│  ✅ 同步:                                                    │
│    • deploy.sh                                              │
│    • docker-compose.yml                                     │
│    • sing-box/config.json.template                          │
│    • sing-box/entrypoint.sh                                 │
│    • Makefile                                               │
│  ❌ 排除:                                                    │
│    • .env, .env.*                                           │
│    • .git, .github                                          │
│    • sing-box/certs/                                        │
│    • *.md, docs/                                            │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  Step 6: 创建 .env 文件                                      │
│  • 从 GitHub Secrets 读取 ENV_FILE                           │
│  • 根据环境使用不同的配置:                                   │
│    - production: 生产环境变量                                │
│    - development: 开发环境变量                               │
│  • 写入到远程服务器 ~/app/.env                               │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  Step 7: 执行 deploy.sh                                      │
│  • 检查环境变量                                              │
│  • 检查/生成 Hysteria2 自签名证书 ⭐                         │
│  • 拉取最新 Docker 镜像                                      │
│  • 启动 Sing-box 服务                                        │
│  • 健康检查                                                  │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
                    ✅ 部署完成
```

## 🔑 关键环境变量（GitHub Secrets）

### 仓库级别 Secrets

这些 Secrets 在仓库设置中配置，所有环境共用：

```yaml
# GCP WIF 认证
GCP_WORKLOAD_IDENTITY_PROVIDER  # WIF 提供者 ID
GCP_SERVICE_ACCOUNT             # 服务账号邮箱
GCP_PROJECT_ID                  # GCP 项目 ID

# VM 信息
GCP_VM_NAME                     # VM 实例名称
GCP_VM_ZONE                     # VM 所在区域
```

### 环境级别 Secrets

这些 Secrets 在环境（production/development）中分别配置：

```yaml
# Production 环境
ENV_FILE  # 包含生产环境的所有配置变量

# Development 环境
ENV_FILE  # 包含开发环境的所有配置变量
```

### ENV_FILE 内容格式

简化版本的 ENV_FILE 应该包含：

```bash
# VLESS + Reality
VLESS_UUID=xxx
REALITY_PRIVATE_KEY=xxx
REALITY_PUBLIC_KEY=xxx
REALITY_SHORT_ID=xxx

# Hysteria2
H2_PASSWORD=xxx
```

**不再需要：**
- ~~DOMAIN~~
- ~~EMAIL~~
- ~~TUIC_UUID~~
- ~~TUIC_PASSWORD~~

## ✅ 当前流程正确性分析

### 1. 证书管理 ✅ 正确

```yaml
# rsync 排除 sing-box/certs/
--exclude "sing-box/certs"
```

✅ **原因：**
- 证书应在服务器上生成，不应从本地同步
- `deploy.sh` 会在服务器上自动检查和生成证书
- 避免权限和路径问题

### 2. 环境变量管理 ✅ 正确

```yaml
# 通过 GitHub Secrets 注入
ssh ${{ env.VM_HOST }} "cat > ${{ env.APP_DIR }}/.env << 'EOF'
${{ secrets.ENV_FILE }}
EOF"
```

✅ **原因：**
- 敏感信息不存储在代码库
- 支持多环境配置
- 安全且灵活

### 3. 文件同步策略 ✅ 优化后正确

```yaml
--exclude ".env"      # 不同步本地 .env
--exclude ".env.*"    # 不同步 .env.development/.env.production
--exclude ".git"      # 不同步 Git 仓库
--exclude ".github"   # 不同步 Actions 配置
--exclude "sing-box/certs"  # 不同步证书
--exclude "*.md"      # 不同步文档
--exclude "docs/"     # 不同步文档目录
```

✅ **原因：**
- 减少同步数据量
- 避免覆盖服务器生成的文件
- 提高部署速度

### 4. 部署脚本执行 ✅ 正确

```yaml
chmod +x deploy.sh && ./deploy.sh
```

✅ **原因：**
- `deploy.sh` 会自动处理所有部署逻辑
- 包括证书检查和生成
- 包括服务启动和健康检查

## 🔄 完整部署示例

### 首次部署

1. **在 GitHub 上配置 Secrets**

```bash
# 仓库级别 Secrets
GCP_WORKLOAD_IDENTITY_PROVIDER=projects/.../locations/.../workloadIdentityPools/...
GCP_SERVICE_ACCOUNT=deploy-sa@project.iam.gserviceaccount.com
GCP_PROJECT_ID=my-project
GCP_VM_NAME=proxy-server
GCP_VM_ZONE=us-central1-a

# Production 环境 Secret
ENV_FILE=
VLESS_UUID=xxx
REALITY_PRIVATE_KEY=xxx
REALITY_PUBLIC_KEY=xxx
REALITY_SHORT_ID=xxx
H2_PASSWORD=xxx

# Development 环境 Secret（如果需要）
ENV_FILE=
VLESS_UUID=xxx-dev
REALITY_PRIVATE_KEY=xxx-dev
...
```

2. **触发部署**

- 进入 GitHub Actions 页面
- 选择 "Deploy to GCP VM (WIF)" workflow
- 点击 "Run workflow"
- 选择分支（main → production, dev → development）

3. **服务器上发生的事情**

```bash
# 1. 文件同步完成
~/app/
├── deploy.sh
├── docker-compose.yml
├── Makefile
└── sing-box/
    ├── config.json.template
    └── entrypoint.sh

# 2. .env 文件创建
~/app/.env  # 从 GitHub Secrets 创建

# 3. deploy.sh 执行
检查环境变量 ✅
检查 Hysteria2 证书...
  ⚠️  证书文件不存在
  📝 生成新的自签名证书...
  ✅ 自签名证书生成成功
  📋 CN: bing.com
  📅 有效期: 100 年
启动服务...
  ⬇️  拉取最新镜像...
  🔥 启动 Sing-box...
⏳ 等待服务就绪...
📊 服务状态:
  sing-box    Up
✅ 部署成功！
```

### 后续更新部署

```bash
# 1. 更新代码
git commit -am "Update configuration"
git push origin main

# 2. 触发 GitHub Actions

# 3. 服务器上
文件同步（覆盖旧文件）
.env 保持不变（从 Secrets 重新生成）
证书检查
  ✅ 证书已存在且有效
  📋 CN: bing.com
  📅 过期时间: Dec 10 2124
重启服务
✅ 更新完成
```

## ⚠️ 注意事项

### 1. 证书持久化 ✅

证书生成后会保存在服务器的 `~/app/sing-box/certs/` 目录，不会被部署覆盖。

### 2. 环境变量更新

如果需要更新环境变量：

```bash
# 方法1: 更新 GitHub Environment Secrets
# 在 GitHub 仓库设置 → Environments → production/development
# 更新 ENV_FILE

# 方法2: 直接在服务器上修改（不推荐）
ssh vm
cd ~/app
vi .env
./deploy.sh
```

### 3. 证书重新生成

如果需要重新生成证书：

```bash
# 方法1: 删除后重新部署
ssh vm
rm -rf ~/app/sing-box/certs/*
# 触发 GitHub Actions 部署

# 方法2: 在服务器上手动生成
ssh vm
cd ~/app
make generate-cert
docker compose restart
```

### 4. 多环境管理

```bash
# Production 部署
# 从 main 分支触发 → 使用 production 环境的 ENV_FILE

# Development 部署
# 从 dev 分支触发 → 使用 development 环境的 ENV_FILE
```

## 🚀 优化建议

### 1. 添加部署验证步骤

可以在 workflow 最后添加验证步骤：

```yaml
- name: Verify Deployment
  run: |
    ssh ${{ env.VM_HOST }} "
      cd ${{ env.APP_DIR }} &&
      docker compose ps &&
      docker logs sing-box --tail 20
    "
```

### 2. 添加回滚机制

在部署失败时自动回滚：

```yaml
- name: Backup Current Version
  run: |
    ssh ${{ env.VM_HOST }} "
      if [ -d ${{ env.APP_DIR }}.backup ]; then
        rm -rf ${{ env.APP_DIR }}.backup
      fi
      cp -r ${{ env.APP_DIR }} ${{ env.APP_DIR }}.backup
    "
```

### 3. 添加通知

部署完成后发送通知（Slack/Discord/Email）。

## 📊 总结

| 项目 | 状态 | 说明 |
|------|------|------|
| 认证方式 | ✅ 正确 | 使用 WIF，无需密钥 |
| 文件同步 | ✅ 优化 | 排除项已更新 |
| 证书管理 | ✅ 正确 | 服务器自动生成 |
| 环境变量 | ✅ 正确 | 使用 GitHub Secrets |
| 部署脚本 | ✅ 正确 | deploy.sh 自动化 |
| 多环境支持 | ✅ 正确 | production/development |

**结论：** GitHub Actions 部署流程与简化版本完全兼容，已优化文件同步策略。✅

---

**相关文档：**
- [WIF 设置指南](./WIF-SETUP-GUIDE.md)
- [多环境配置](./MULTI-ENV-SETUP.md)
- [部署脚本说明](../README.md#部署)
