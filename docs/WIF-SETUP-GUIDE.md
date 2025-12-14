# GCP Workload Identity Federation (WIF) 配置指南

## 📋 概述

本项目使用 Google Cloud Workload Identity Federation (WIF) 实现 GitHub Actions 到 GCP VM 的安全部署，无需管理 SSH 私钥。

---

## 🔧 一、前置准备

### 1.1 本地环境要求

确保已安装以下工具：

```bash
# 检查 gcloud CLI
gcloud --version

# 检查 GitHub CLI
gh --version

# 检查 git
git --version
```

### 1.2 GCP 项目信息

准备以下信息（运行脚本时需要）：

| 配置项 | 说明 | 示例 |
|--------|------|------|
| **GCP Project ID** | 您的 GCP 项目 ID | `my-project-123` |
| **GitHub Repository** | 格式：`owner/repo` | `kyson/proxy-builder` |
| **VM Name** | GCP 虚拟机名称 | `proxy-vm` |
| **VM Zone** | 虚拟机所在区域 | `us-central1-a` |

---

## 🚀 二、执行配置脚本

### 2.1 运行 setup-wif.sh

在项目根目录执行：

```bash
make setup-wif
```

或直接运行：

```bash
chmod +x scripts/setup-wif.sh
./scripts/setup-wif.sh
```

### 2.2 脚本执行流程

脚本会自动完成以下操作：

#### ✅ 步骤 1: 启用必要的 GCP API
- IAM API
- Cloud Resource Manager API
- IAM Credentials API
- Compute Engine API

#### ✅ 步骤 2: 创建 Service Account
- 名称：`github-deploy`
- 用途：GitHub Actions 使用此账号部署

#### ✅ 步骤 3: 授予权限
- `roles/compute.instanceAdmin.v1` - 管理 VM 实例
- `roles/compute.osLogin` - 通过 OS Login SSH 登录
- `roles/iam.serviceAccountUser` - 使用 Service Account

#### ✅ 步骤 4: 创建 Workload Identity Pool
- 名称：`github-pool`
- 用途：管理外部身份（GitHub）

#### ✅ 步骤 5: 创建 Workload Identity Provider
- 名称：`github-provider`
- 映射 GitHub Token 到 GCP 身份

#### ✅ 步骤 6: 绑定 GitHub Repository
- 允许指定的 GitHub 仓库使用 Service Account

#### ✅ 步骤 7: 自动设置 GitHub Secrets
自动将以下 Secrets 写入 GitHub 仓库：
- `GCP_PROJECT_ID`
- `GCP_WORKLOAD_IDENTITY_PROVIDER`
- `GCP_SERVICE_ACCOUNT`
- `GCP_VM_NAME`（如果提供）
- `GCP_VM_ZONE`（如果提供）

---

## 📝 三、GitHub Secrets 配置清单

### 3.1 自动配置的 Secrets（由脚本创建）

| Secret 名称 | 说明 | 示例值 |
|-------------|------|--------|
| `GCP_PROJECT_ID` | GCP 项目 ID | `my-project-123` |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | WIF Provider 完整路径 | `projects/123.../locations/global/workloadIdentityPools/github-pool/providers/github-provider` |
| `GCP_SERVICE_ACCOUNT` | Service Account 邮箱 | `github-deploy@my-project-123.iam.gserviceaccount.com` |
| `GCP_VM_NAME` | VM 实例名称 | `proxy-vm` |
| `GCP_VM_ZONE` | VM 所在区域 | `us-central1-a` |

### 3.2 需要手动配置的 Secrets

| Secret 名称 | 说明 | 如何获取 |
|-------------|------|----------|
| `ENV_FILE` | 完整的 `.env` 文件内容 | 复制本地 `.env` 文件的全部内容 |

**设置 ENV_FILE 的方法：**

```bash
# 方法 1: 使用 make 命令（推荐）
make push-env

# 方法 2: 手动设置
gh secret set ENV_FILE < .env
```

---

## 🔍 四、验证配置

### 4.1 检查 GitHub Secrets

在 GitHub 仓库页面：
1. 进入 `Settings` → `Secrets and variables` → `Actions`
2. 确认以下 Secrets 存在：
   - ✅ `GCP_PROJECT_ID`
   - ✅ `GCP_WORKLOAD_IDENTITY_PROVIDER`
   - ✅ `GCP_SERVICE_ACCOUNT`
   - ✅ `GCP_VM_NAME`
   - ✅ `GCP_VM_ZONE`
   - ✅ `ENV_FILE`

### 4.2 检查 GCP 配置

```bash
# 检查 Service Account
gcloud iam service-accounts list --project=YOUR_PROJECT_ID

# 检查 Workload Identity Pool
gcloud iam workload-identity-pools list --location=global --project=YOUR_PROJECT_ID

# 检查 VM 是否启用 OS Login
gcloud compute instances describe YOUR_VM_NAME --zone=YOUR_VM_ZONE --format="get(metadata.items[key=enable-oslogin].value)"
```

### 4.3 测试部署

推送代码到 `main` 分支触发部署：

```bash
git add .
git commit -m "test: trigger WIF deployment"
git push origin main
```

在 GitHub Actions 页面查看部署日志。

---

## 🛠️ 五、故障排查

### 问题 1: Permission Denied

**症状：** GitHub Actions 报错 `Permission denied`

**解决方案：**
```bash
# 确保 VM 启用了 OS Login
gcloud compute instances add-metadata YOUR_VM_NAME \
  --zone=YOUR_VM_ZONE \
  --metadata enable-oslogin=TRUE

# 重新授予权限
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:github-deploy@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/compute.osLogin"
```

### 问题 2: Workload Identity Provider 不存在

**症状：** `Error: Workload Identity Provider not found`

**解决方案：**
```bash
# 重新运行配置脚本
make setup-wif
```

### 问题 3: SSH 连接失败

**症状：** `Could not resolve hostname`

**解决方案：**
- 确认 `GCP_VM_NAME` 和 `GCP_VM_ZONE` 正确
- 检查 VM 是否正在运行
- 确认 Service Account 有 `compute.instanceAdmin.v1` 权限

---

## 📚 六、与旧配置的对比

### 旧方式（SSH Key）

```yaml
- name: Setup SSH
  run: |
    echo "${{ secrets.SSH_PRIVATE_KEY }}" > ~/.ssh/id_ed25519
    chmod 600 ~/.ssh/id_ed25519
```

**缺点：**
- ❌ 需要手动管理 SSH 密钥
- ❌ 密钥泄露风险
- ❌ 密钥轮换困难

### 新方式（WIF）

```yaml
- name: Authenticate to Google Cloud
  uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
    service_account: ${{ secrets.GCP_SERVICE_ACCOUNT }}
```

**优点：**
- ✅ 无需管理密钥
- ✅ 自动轮换凭证
- ✅ 细粒度权限控制
- ✅ 审计日志完整

---

## 🔐 七、安全最佳实践

1. **最小权限原则**
   - Service Account 仅授予必要的权限
   - 仅允许特定 GitHub 仓库使用

2. **定期审计**
   ```bash
   # 查看 Service Account 的权限
   gcloud projects get-iam-policy YOUR_PROJECT_ID \
     --flatten="bindings[].members" \
     --filter="bindings.members:github-deploy@*"
   ```

3. **监控访问日志**
   - 在 GCP Console 查看 Cloud Audit Logs
   - 监控异常的 SSH 登录

---

## 📞 八、获取帮助

如果遇到问题：

1. 查看 GitHub Actions 日志
2. 查看 GCP Audit Logs
3. 运行 `gcloud compute config-ssh --dry-run` 检查 SSH 配置
4. 确认所有 API 已启用：`gcloud services list --enabled`

---

## ✅ 配置完成检查清单

- [ ] 已安装 `gcloud` 和 `gh` CLI
- [ ] 已运行 `make setup-wif`
- [ ] GitHub Secrets 中有 6 个必需的 Secret
- [ ] VM 已启用 OS Login
- [ ] 推送代码触发部署成功
- [ ] 可以在 GitHub Actions 中看到部署日志

**完成以上步骤后，您的 WIF 配置就完成了！** 🎉
