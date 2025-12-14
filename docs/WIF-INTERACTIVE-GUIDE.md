# WIF 配置脚本交互体验升级

## 🎉 新功能

`setup-wif.sh` 脚本现在提供了**完全交互式**的配置体验！

---

## ✨ 主要改进

### 1. **GCP 项目选择**

**之前**：只能输入或使用默认项目
```bash
Enter GCP Project ID [my-project]: 
```

**现在**：可以从列表中选择
```bash
📋 Step 1: Select GCP Project

Fetching your GCP projects...

Available projects:
  1. my-project-123 (current)
  2. test-project-456
  3. prod-project-789
  0. Enter manually

Select project (0-3) [default: my-project-123]: 
```

**特性**：
- ✅ 自动列出您账户下的所有 GCP 项目
- ✅ 标记当前默认项目 `(current)`
- ✅ 支持数字选择（快速）
- ✅ 支持直接回车使用默认项目
- ✅ 支持手动输入（选择 0）

---

### 2. **VM 实例选择**

**之前**：手动输入 VM 名称和 Zone
```bash
Enter VM Name: proxy-vm
Enter VM Zone: us-central1-a
```

**现在**：可视化列表选择
```bash
📋 Step 3: Select VM Instance

Fetching VM instances in project 'my-project-123'...

Available VM instances:
  1. proxy-vm-prod
      Zone: us-central1-a | Status: 🟢 RUNNING
  2. proxy-vm-dev
      Zone: us-west1-b | Status: 🟢 RUNNING
  3. test-vm
      Zone: asia-east1-a | Status: 🔴 TERMINATED
  0. Enter manually

Select VM (0-3): 
```

**特性**：
- ✅ 自动列出项目中的所有 VM 实例
- ✅ 显示 Zone 和运行状态
- ✅ 状态图标：🟢 运行中 / 🔴 已停止 / ⚪ 其他
- ✅ 自动检测并填充 Zone（无需手动输入）
- ✅ 如果选择已停止的 VM，会警告并确认
- ✅ 支持手动输入（选择 0）

---

### 3. **GitHub 仓库确认**

**改进**：自动检测 Git 远程仓库
```bash
📋 Step 2: Confirm GitHub Repository

GitHub Repository [kysonzou/proxy-builder]: 
```

直接回车即可使用检测到的仓库。

---

## 🎯 使用流程

### 完整示例

```bash
make setup-wif
```

**交互流程**：

```
🚀 Setting up Workload Identity Federation for GitHub Actions

📋 Step 1: Select GCP Project

Fetching your GCP projects...

Available projects:
  1. kyson-lab (current)
  2. kyson-prod
  0. Enter manually

Select project (0-2) [default: kyson-lab]: 1
✅ Using Project ID: kyson-lab

📋 Step 2: Confirm GitHub Repository

GitHub Repository [kysonzou/proxy-builder]: ↵
✅ Using Repository: kysonzou/proxy-builder

Enable necessary APIs...
✓ iam.googleapis.com
✓ cloudresourcemanager.googleapis.com
✓ iamcredentials.googleapis.com
✓ compute.googleapis.com

Creating Service Account (github-deploy)...
Service Account already exists, skipping creation.

Granting permissions...
✓ roles/compute.instanceAdmin.v1
✓ roles/compute.osAdminLogin
✓ roles/iam.serviceAccountUser

Creating Workload Identity Pool (github-pool)...
Pool already exists, skipping creation.

Creating Workload Identity Provider (github-provider)...
Provider already exists, skipping creation.

Binding GitHub repo to Service Account...
✓ Bound

📋 Step 3: Select VM Instance

Fetching VM instances in project 'kyson-lab'...

Available VM instances:
  1. proxy-vm
      Zone: us-central1-a | Status: 🟢 RUNNING
  0. Enter manually

Select VM (0-1): 1
✅ Selected VM: proxy-vm (Zone: us-central1-a)

🔐 Checking OS Login configuration...
✅ OS Login is already enabled

✅ Setup Complete!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Workload Identity Provider: projects/123.../github-provider
Service Account: github-deploy@kyson-lab.iam.gserviceaccount.com
VM Name: proxy-vm
VM Zone: us-central1-a
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Setting GitHub Secrets...
✓ GCP_PROJECT_ID
✓ GCP_WORKLOAD_IDENTITY_PROVIDER
✓ GCP_SERVICE_ACCOUNT
✓ GCP_VM_NAME
✓ GCP_VM_ZONE

✅ All GitHub Secrets have been set!

📋 Next Steps:
   1. Run 'make push-env' to upload your .env file
   2. Push code to trigger deployment: 'git push origin main'

Done.
```

---

## 🛡️ 错误处理

### 场景 1: 没有 VM 实例

```bash
📋 Step 3: Select VM Instance

Fetching VM instances in project 'empty-project'...
⚠️  No VM instances found in project 'empty-project'

Enter VM Name manually: my-new-vm
Enter VM Zone (e.g., us-central1-a): us-central1-a
```

### 场景 2: 选择已停止的 VM

```bash
Select VM (0-3): 3
⚠️  Warning: VM 'test-vm' is not running (status: TERMINATED)
   Continue anyway? (y/n): n
Select VM (0-3): 1
✅ Selected VM: proxy-vm (Zone: us-central1-a)
```

### 场景 3: 无效输入

```bash
Select VM (0-3): 99
Invalid selection. Please try again.
Select VM (0-3): abc
Invalid selection. Please try again.
Select VM (0-3): 1
✅ Selected VM: proxy-vm (Zone: us-central1-a)
```

---

## 📊 对比总结

| 功能 | 旧版本 | 新版本 |
|------|--------|--------|
| **项目选择** | 手动输入 | 📋 列表选择 + 手动输入 |
| **VM 选择** | 手动输入名称和 Zone | 📋 可视化列表 + 自动检测 Zone |
| **状态显示** | 无 | 🟢🔴 实时状态图标 |
| **错误提示** | 基础 | ⚠️ 详细警告和确认 |
| **用户体验** | 需要记住资源名称 | 🎯 直观选择，无需记忆 |
| **容错性** | 低 | ✅ 高（支持重试和回退） |

---

## 🎨 设计理念

1.  **渐进式增强**：保留手动输入选项（选择 0），适应各种场景
2.  **智能默认**：自动检测并标记当前/推荐选项
3.  **可视化反馈**：使用 emoji 和颜色增强可读性
4.  **防呆设计**：对危险操作（如选择已停止的 VM）进行二次确认
5.  **步骤清晰**：使用 📋 Step 1/2/3 标记，流程一目了然

---

## 🚀 快速开始

```bash
# 一键配置 WIF
make setup-wif

# 只需要做 3 个选择：
# 1. 选择 GCP 项目（或回车使用默认）
# 2. 确认 GitHub 仓库（或回车使用检测值）
# 3. 选择 VM 实例（自动填充 Zone）

# 完成！所有 GitHub Secrets 已自动配置
```

---

## 💡 提示

- **首次使用**：建议选择列表中的选项，确保资源存在
- **高级用户**：可以选择 `0` 手动输入，支持尚未创建的资源
- **多项目管理**：脚本会记住您的选择，下次运行更快
- **CI/CD 集成**：如需非交互式运行，可以通过环境变量预设值（未来功能）

---

## 📝 更新日志

### v2.0 - 交互式体验升级

- ✅ 新增 GCP 项目列表选择
- ✅ 新增 VM 实例可视化选择
- ✅ 新增运行状态显示（🟢🔴⚪）
- ✅ 新增智能 Zone 自动检测
- ✅ 改进错误处理和用户提示
- ✅ 优化输出格式和步骤标记

### v1.0 - 初始版本

- ✅ 基础 WIF 配置功能
- ✅ 手动输入模式
