# WIF 配置总结

## ✅ 已完成的工作

我已经为您整理好了完整的 WIF 配置系统，包括：

### 1. 核心文件

| 文件 | 作用 | 您需要做什么 |
|------|------|-------------|
| `scripts/setup-wif.sh` | 自动配置 GCP WIF | 运行 `make setup-wif` |
| `.github/workflows/deploy.yml` | GitHub Actions 部署流程 | 无需修改，自动运行 |
| `Makefile` | 便捷命令工具 | 使用 `make` 命令 |

### 2. 文档文件

| 文件 | 内容 | 适用场景 |
|------|------|---------|
| `docs/WIF-CHECKLIST.md` | 快速配置清单 | ⭐ **首次配置必读** |
| `docs/WIF-SETUP-GUIDE.md` | 完整配置指南 | 详细了解每个步骤 |
| `docs/WIF-FLOWCHART.md` | 可视化流程图 | 理解整体架构 |
| `README.md` | 项目主文档 | 已更新 WIF 说明 |

---

## 🎯 您只需要做 3 件事

### 第 1 步：配置 WIF（一次性）

```bash
make setup-wif
```

**脚本会问您 4 个问题：**
1. GCP Project ID（您的 GCP 项目 ID）
2. GitHub Repository（格式：owner/repo，会自动检测）
3. VM Name（您的虚拟机名称）
4. VM Zone（虚拟机所在区域，如 us-central1-a）

**脚本会自动：**
- ✅ 创建 Service Account
- ✅ 创建 Workload Identity Pool 和 Provider
- ✅ 配置所有 IAM 权限
- ✅ 设置 5 个 GitHub Secrets

---

### 第 2 步：上传环境变量

```bash
make push-env
```

这会将您的 `.env` 文件内容上传到 GitHub Secrets（`ENV_FILE`）。

---

### 第 3 步：推送代码触发部署

```bash
git push origin main
```

GitHub Actions 会自动：
1. 使用 WIF 认证到 GCP
2. 通过 OS Login SSH 连接到 VM
3. 同步代码和配置
4. 执行部署脚本

---

## 📋 配置清单

### setup-wif.sh 需要的信息

| 配置项 | 说明 | 示例 |
|--------|------|------|
| GCP Project ID | 您的 GCP 项目 ID | `my-project-123` |
| GitHub Repository | 格式：owner/repo | `kyson/proxy-builder` |
| VM Name | 虚拟机名称 | `proxy-vm` |
| VM Zone | 虚拟机区域 | `us-central1-a` |

### deploy.yml 需要的 GitHub Secrets

**自动设置（5个）：**
- ✅ `GCP_PROJECT_ID`
- ✅ `GCP_WORKLOAD_IDENTITY_PROVIDER`
- ✅ `GCP_SERVICE_ACCOUNT`
- ✅ `GCP_VM_NAME`
- ✅ `GCP_VM_ZONE`

**手动设置（1个）：**
- ⚠️ `ENV_FILE` - 运行 `make push-env`

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

### 检查 VM OS Login

```bash
gcloud compute instances describe YOUR_VM_NAME \
  --zone=YOUR_VM_ZONE \
  --format="get(metadata.items[key=enable-oslogin].value)"
```

应该返回：`TRUE`

如果不是，运行：
```bash
gcloud compute instances add-metadata YOUR_VM_NAME \
  --zone=YOUR_VM_ZONE \
  --metadata enable-oslogin=TRUE
```

---

## 🆚 与旧配置的区别

### 旧方式（SSH Key）

**需要配置的 Secrets：**
- `SSH_PRIVATE_KEY` - 手动生成和管理
- `VM_HOST` - 手动输入
- `VM_USER` - 手动输入
- `ENV_FILE` - 手动上传

**缺点：**
- ❌ 需要手动管理 SSH 密钥
- ❌ 密钥可能泄露
- ❌ 密钥轮换困难

### 新方式（WIF）

**需要配置的 Secrets：**
- 自动设置 5 个（运行 `make setup-wif`）
- 手动设置 1 个（运行 `make push-env`）

**优点：**
- ✅ 无需管理 SSH 密钥
- ✅ 自动轮换凭证
- ✅ 细粒度权限控制
- ✅ 符合 Google 安全最佳实践

---

## 🚀 快速开始

```bash
# 1. 配置 WIF（一次性）
make setup-wif

# 2. 上传环境变量
make push-env

# 3. 推送代码触发部署
git push origin main
```

---

## 📚 详细文档

- **快速开始**：[WIF-CHECKLIST.md](./WIF-CHECKLIST.md)
- **完整指南**：[WIF-SETUP-GUIDE.md](./WIF-SETUP-GUIDE.md)
- **流程图**：[WIF-FLOWCHART.md](./WIF-FLOWCHART.md)

---

## 🛠️ 常用命令

```bash
# 生成工具
make uuid          # 生成 UUID
make short-id      # 生成 Short ID
make password      # 生成密码
make reality-key   # 生成 REALITY 密钥对

# 配置工具
make setup-wif     # 配置 WIF（一次性）
make push-env      # 上传 .env 到 GitHub Secrets

# 查看帮助
make help          # 显示所有可用命令
```

---

## ✅ 配置完成后

您可以删除以下旧的 GitHub Secrets（如果存在）：
- ❌ `SSH_PRIVATE_KEY`
- ❌ `VM_HOST`
- ❌ `VM_USER`

这些已经不再需要了！
