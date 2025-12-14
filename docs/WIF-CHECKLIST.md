# WIF 配置快速清单

## 📋 setup-wif.sh 需要的信息

运行 `make setup-wif` 时，脚本会询问以下信息（**全部必填**）：

| 配置项 | 说明 | 在哪里获取 |
|--------|------|-----------|
| **GCP Project ID** | GCP 项目 ID | GCP Console 顶部或 `gcloud config get-value project` |
| **GitHub Repository** | 格式：`owner/repo` | 自动检测，或手动输入如 `kyson/proxy-builder` |
| **VM Name** | 虚拟机名称 | GCP Console → Compute Engine → VM instances |
| **VM Zone** | 虚拟机区域 | 同上，如 `us-central1-a`（脚本会自动检测） |

**脚本会自动完成：**
- ✅ 验证 VM 是否存在（如果找到会自动检测 Zone）
- ✅ 检查并启用 OS Login（询问是否自动启用）
- ✅ 创建 Service Account（如已存在则跳过）
- ✅ 创建 Workload Identity Pool 和 Provider（如已存在则跳过）
- ✅ 配置所有必要的 IAM 权限
- ✅ 自动设置所有 6 个 GitHub Secrets（除了 ENV_FILE）

---

## 🔑 deploy.yml 需要的 GitHub Secrets

### 自动配置（由 setup-wif.sh 创建）

| Secret 名称 | 来源 |
|-------------|------|
| `GCP_PROJECT_ID` | 自动设置 ✅ |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | 自动设置 ✅ |
| `GCP_SERVICE_ACCOUNT` | 自动设置 ✅ |
| `GCP_VM_NAME` | 自动设置 ✅ |
| `GCP_VM_ZONE` | 自动设置 ✅ |

### 需要手动配置

| Secret 名称 | 内容 | 如何设置 |
|-------------|------|----------|
| `ENV_FILE` | 完整的 `.env` 文件内容 | 运行 `make push-env` |

---

## ✅ 完整配置步骤（3步）

```bash
# 步骤 1: 配置 WIF（一次性）
make setup-wif

# 步骤 2: 上传环境变量（每次 .env 更新后）
make push-env

# 步骤 3: 推送代码触发部署
git push origin main
```

---

## 🔍 验证配置

### 检查 GitHub Secrets

访问：`https://github.com/YOUR_REPO/settings/secrets/actions`

应该看到 **6 个 Secrets**：
- ✅ GCP_PROJECT_ID
- ✅ GCP_WORKLOAD_IDENTITY_PROVIDER
- ✅ GCP_SERVICE_ACCOUNT
- ✅ GCP_VM_NAME
- ✅ GCP_VM_ZONE
- ✅ ENV_FILE

### 检查 VM 配置

```bash
# 确认 VM 启用了 OS Login
gcloud compute instances describe YOUR_VM_NAME \
  --zone=YOUR_VM_ZONE \
  --format="get(metadata.items[key=enable-oslogin].value)"

# 应该返回: TRUE
```

如果返回空或 FALSE，运行：

```bash
gcloud compute instances add-metadata YOUR_VM_NAME \
  --zone=YOUR_VM_ZONE \
  --metadata enable-oslogin=TRUE
```

---

## 🚨 常见问题

### Q: setup-wif.sh 报错 "gcloud not found"
**A:** 安装 gcloud CLI: https://cloud.google.com/sdk/docs/install

### Q: GitHub Actions 报错 "Permission denied"
**A:** 确认 VM 启用了 OS Login（见上方检查命令）

### Q: 如何更新 .env 文件？
**A:** 修改本地 `.env` 后运行 `make push-env`

### Q: 如何删除旧的 SSH Key 配置？
**A:** 在 GitHub Settings → Secrets 中删除 `SSH_PRIVATE_KEY`、`VM_HOST`、`VM_USER`

---

## 📚 详细文档

查看完整配置指南：[WIF-SETUP-GUIDE.md](./WIF-SETUP-GUIDE.md)
