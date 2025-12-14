# 环境变量管理指南

## 📋 概述

项目使用 GitHub Environment Secrets 来管理不同环境的配置，所有环境变量存储在一个名为 `ENV_FILE` 的 secret 中。

## 🔑 配置方式对比

### ✅ 新方式（推荐）

将整个 `.env` 文件作为单个 `ENV_FILE` secret 上传：

```bash
# 上传到 production 环境
make push-env-prod

# 上传到 development 环境
make push-env-dev
```

**优点：**
- ✅ 与 deploy.yml 完全一致
- ✅ 一次性上传所有变量
- ✅ 易于管理和更新
- ✅ 支持注释和格式

### ❌ 旧方式（已弃用）

将每个变量作为独立的 secret：

```bash
gh secret set VLESS_UUID --env production --body "xxx"
gh secret set REALITY_PRIVATE_KEY --env production --body "xxx"
...
```

**缺点：**
- ❌ 与 deploy.yml 不一致
- ❌ 需要逐个设置变量
- ❌ 管理复杂

## 🚀 快速开始

### 1. 创建环境变量文件

```bash
# 复制示例文件
cp .env.production.example .env.production

# 编辑配置
vim .env.production
```

**简化版本的 `.env.production` 内容：**

```bash
# VLESS + Reality
VLESS_UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
REALITY_PRIVATE_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
REALITY_PUBLIC_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
REALITY_SHORT_ID=xxxxxxxxxxxxxxxx

# Hysteria2 (使用自签名证书)
H2_PASSWORD=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

### 2. 生成密钥

使用 Makefile 提供的命令：

```bash
# 生成 VLESS UUID
make uuid

# 生成 Reality 密钥对
make reality-key

# 生成 Reality Short ID
make short-id

# 生成 Hysteria2 密码
make password
```

### 3. 上传到 GitHub

```bash
# 上传生产环境配置
make push-env-prod

# 或上传开发环境配置
make push-env-dev
```

**执行示例：**

```bash
$ make push-env-prod
📦 Pushing .env.production as ENV_FILE to 'production' environment...

✓ Set secret ENV_FILE for kysonzou/proxy-builder

✅ Production environment ENV_FILE updated!

📋 Content pushed:
VLESS_UUID=a1b2c3d4-e5f6-7890-abcd-ef1234567890
REALITY_PRIVATE_KEY=SMO...
REALITY_PUBLIC_KEY=dF9...
REALITY_SHORT_ID=a1b2c3d4e5f67890
H2_PASSWORD=xY9zW8...
```

## 📊 GitHub Secrets 结构

### 仓库级别 Secrets

存储在 `Settings → Secrets and variables → Actions → Repository secrets`：

```
GCP_WORKLOAD_IDENTITY_PROVIDER
GCP_SERVICE_ACCOUNT
GCP_PROJECT_ID
GCP_VM_NAME
GCP_VM_ZONE
```

### 环境级别 Secrets

存储在 `Settings → Environments → [production/development] → Environment secrets`：

#### Production 环境

```
ENV_FILE  ← 包含 .env.production 的完整内容
```

#### Development 环境

```
ENV_FILE  ← 包含 .env.development 的完整内容
```

## 🔄 更新环境变量

### 方法 1: 通过 Makefile（推荐）

```bash
# 1. 更新本地文件
vim .env.production

# 2. 重新上传
make push-env-prod
```

### 方法 2: 通过 GitHub Web UI

```bash
# 1. 进入仓库设置
Settings → Environments → production → Environment secrets

# 2. 点击 ENV_FILE → Update secret

# 3. 粘贴新的环境变量内容
```

### 方法 3: 使用 GitHub CLI（手动）

```bash
# 上传整个文件
gh secret set ENV_FILE --env production < .env.production

# 或交互式输入
gh secret set ENV_FILE --env production
# 然后粘贴内容
```

## 🔍 验证配置

### 查看当前 Secrets

```bash
# 列出所有环境的 secrets
gh secret list

# 查看特定环境的 secrets
gh secret list --env production
```

**示例输出：**

```
NAME                             UPDATED
ENV_FILE                         3 minutes ago
GCP_PROJECT_ID                   2 days ago
GCP_SERVICE_ACCOUNT             2 days ago
GCP_VM_NAME                     2 days ago
GCP_VM_ZONE                     2 days ago
GCP_WORKLOAD_IDENTITY_PROVIDER  2 days ago
```

### 测试部署

```bash
# 触发 GitHub Actions 部署
# GitHub → Actions → Deploy to GCP VM (WIF) → Run workflow
```

查看日志中的环境变量部分：

```
Create/Update .env file
  Writing environment variables to remote server...
  ✓ .env file created
```

## 📝 环境变量说明

### 简化版本所需变量

| 变量名 | 用途 | 生成方式 |
|--------|------|---------|
| `VLESS_UUID` | VLESS 用户 ID | `make uuid` |
| `REALITY_PRIVATE_KEY` | Reality 私钥 | `make reality-key` |
| `REALITY_PUBLIC_KEY` | Reality 公钥 | `make reality-key` |
| `REALITY_SHORT_ID` | Reality 短 ID | `make short-id` |
| `H2_PASSWORD` | Hysteria2 密码 | `make password` |

### 已移除的变量

以下变量在简化版本中**不再需要**：

| 变量名 | 原用途 | 移除原因 |
|--------|--------|---------|
| ~~`DOMAIN`~~ | 域名 | 不再需要域名 |
| ~~`EMAIL`~~ | Let's Encrypt 邮箱 | 不使用 Let's Encrypt |
| ~~`TUIC_UUID`~~ | TUIC 用户 ID | 移除 TUIC 协议 |
| ~~`TUIC_PASSWORD`~~ | TUIC 密码 | 移除 TUIC 协议 |

## ⚠️ 注意事项

### 1. 安全性

- ✅ **不要** 将 `.env.production` 或 `.env.development` 提交到 Git
- ✅ 这些文件已在 `.gitignore` 中排除
- ✅ 使用 GitHub Secrets 安全存储
- ✅ 定期更换密码和密钥

### 2. 多环境管理

```bash
# 开发环境
make push-env-dev    # 从 .env.development 上传

# 生产环境
make push-env-prod   # 从 .env.production 上传
```

### 3. 内容格式

ENV_FILE 支持：

```bash
# 注释（会被保留，但不影响使用）
# 这是一个注释

# 空行也会被保留

# 环境变量
VLESS_UUID=xxx
REALITY_PRIVATE_KEY=xxx
```

### 4. 更新后的部署

更新环境变量后，需要重新部署才能生效：

```bash
# 1. 上传新的环境变量
make push-env-prod

# 2. 触发 GitHub Actions 部署
# 或者在服务器上手动重启
ssh vm
cd ~/app
./deploy.sh
```

## 🛠️ 故障排除

### 问题 1: GitHub CLI 未安装

```bash
# macOS
brew install gh

# Ubuntu/Debian
sudo apt install gh

# 认证
gh auth login
```

### 问题 2: 权限不足

确保你有仓库的 admin 或 write 权限：

```bash
# 检查权限
gh api repos/$OWNER/$REPO --jq .permissions
```

### 问题 3: Secret 上传失败

```bash
# 检查文件是否存在
ls -la .env.production

# 检查文件内容
cat .env.production

# 手动设置（用于调试）
gh secret set ENV_FILE --env production --body "$(cat .env.production)"
```

### 问题 4: 部署时环境变量不生效

检查 deploy.yml 中的环境选择逻辑：

```yaml
environment:
  name: ${{ github.ref == 'refs/heads/main' && 'production' || 'development' }}
```

- `main` 分支 → `production` 环境
- 其他分支 → `development` 环境

## 📚 相关文档

- [GitHub Actions 部署流程](./GITHUB-ACTIONS-DEPLOYMENT.md)
- [多环境配置](./MULTI-ENV-SETUP.md)
- [快速开始指南](./QUICKSTART.md)

## 🔗 相关命令

```bash
# 查看所有可用命令
make help

# 生成密钥
make uuid
make short-id
make password
make reality-key

# 上传环境变量
make push-env-prod
make push-env-dev

# 查看 GitHub Secrets
gh secret list
gh secret list --env production
gh secret list --env development
```

---

**重要提示：** 此文档描述的是**简化版本**的配置方式。如果你使用的是完整版本（包含域名、Let's Encrypt、TUIC 等），请参考相应版本的文档。
