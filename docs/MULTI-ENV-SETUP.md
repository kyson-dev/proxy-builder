# 多环境部署指南

## 🎯 目标

实现 `main` 和 `dev` 分支部署到不同的 VM，完全隔离生产和测试环境。

---

## 📐 架构设计

```
┌─────────────────────────────────────────────────────────────┐
│                     GitHub Repository                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   main 分支                      dev 分支                    │
│      │                              │                        │
│      ▼                              ▼                        │
│   production 环境               development 环境             │
│      │                              │                        │
│      ▼                              ▼                        │
│   生产 VM                        测试 VM                     │
│   (instance-20250515)            (dev-instance)              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 📁 本地文件结构

```
项目根目录/
├── .env.production.example     # 生产环境配置模板（提交到 Git）
├── .env.development.example    # 开发环境配置模板（提交到 Git）
├── .env.production             # 生产环境配置（不提交，含敏感信息）
├── .env.development            # 开发环境配置（不提交，含敏感信息）
└── .gitignore                  # 忽略 .env.* 文件
```

---

## ⚙️ 完整配置流程

### 步骤 1: 创建环境配置文件

```bash
# 复制模板
cp .env.production.example .env.production
cp .env.development.example .env.development

# 编辑配置
vim .env.production
vim .env.development
```

**配置内容示例：**

`.env.production`:
```bash
DOMAIN=kyson.site
EMAIL=admin@kyson.site
VLESS_UUID=prod-uuid-xxx
REALITY_PRIVATE_KEY=prod-private-key-xxx
# ... 其他配置
```

`.env.development`:
```bash
DOMAIN=dev.kyson.site  # 使用不同的域名
EMAIL=admin@kyson.site
VLESS_UUID=dev-uuid-xxx  # 可以使用不同的凭证
REALITY_PRIVATE_KEY=dev-private-key-xxx
# ... 其他配置
```

---

### 步骤 2: 在 GitHub 创建环境

1. 访问：`https://github.com/YOUR_REPO/settings/environments`
2. 点击 **New environment**
3. 创建两个环境：
   - `production`
   - `development`

**可选的保护规则（production）：**
- ✅ Required reviewers（需要审批）
- ✅ Wait timer（延迟部署）
- ✅ Deployment branches: `main` only

---

### 步骤 3: 配置 WIF（每个环境运行一次）

```bash
# 配置生产环境
make setup-wif
# 选择 1 (production)
# 选择生产 VM

# 配置开发环境
make setup-wif
# 选择 2 (development)
# 选择测试 VM
```

**脚本会自动设置以下环境 Secrets：**
- `GCP_PROJECT_ID`
- `GCP_WORKLOAD_IDENTITY_PROVIDER`
- `GCP_SERVICE_ACCOUNT`
- `GCP_VM_NAME`（不同环境不同 VM）
- `GCP_VM_ZONE`

---

### 步骤 4: 推送环境变量

```bash
# 推送生产环境配置
make push-env-prod

# 推送开发环境配置
make push-env-dev
```

**验证 Secrets 已设置：**
```bash
gh secret list --env production
gh secret list --env development
```

---

### 步骤 5: 测试部署

```bash
# 测试开发环境部署
git checkout dev
git push origin dev

# 测试生产环境部署
git checkout main
git push origin main
```

---

## 🔄 日常工作流程

### 开发新功能

```bash
# 1. 在 dev 分支开发
git checkout dev
# ... 修改代码 ...
git add .
git commit -m "feat: new feature"

# 2. 推送触发部署到测试环境
git push origin dev
# → 自动部署到 development 环境的 VM

# 3. 验证测试环境
# SSH 到测试 VM 检查服务

# 4. 测试通过后合并到 main
git checkout main
git merge dev

# 5. 推送触发部署到生产环境
git push origin main
# → 自动部署到 production 环境的 VM
```

### 更新环境配置

```bash
# 更新生产环境配置
vim .env.production
make push-env-prod

# 更新开发环境配置
vim .env.development
make push-env-dev

# 重新部署以应用新配置
git checkout main && git push origin main  # 生产
git checkout dev && git push origin dev    # 开发
```

---

## 📋 命令速查

| 命令 | 说明 |
|------|------|
| `make setup-wif` | 配置 WIF（交互式选择环境） |
| `make push-env-prod` | 推送 `.env.production` 到 production 环境 |
| `make push-env-dev` | 推送 `.env.development` 到 development 环境 |
| `gh secret list --env production` | 查看 production 环境的 Secrets |
| `gh secret list --env development` | 查看 development 环境的 Secrets |

---

## 🔒 安全建议

### 1. 分支保护

为 `main` 分支设置保护规则：
- Settings → Branches → Add rule
- ✅ Require pull request reviews
- ✅ Require status checks to pass

### 2. 环境保护

为 `production` 环境设置保护：
- Settings → Environments → production
- ✅ Required reviewers
- ✅ Restrict to `main` branch only

### 3. 凭证隔离

- 生产和开发使用**不同的**密码/UUID
- 即使开发环境泄露也不影响生产

---

## ❓ 常见问题

### Q: 两个环境可以使用同一个 VM 吗？

**不建议**。多环境的目的就是隔离，共用 VM 会导致：
- 配置相互覆盖
- 无法独立测试
- 失去了多环境的意义

### Q: 开发环境必须有单独的域名吗？

**建议但非必须**。
- **有独立域名**：更规范，可以独立测试
- **无独立域名**：使用 IP 或端口区分也可以

### Q: WIF 需要为每个环境配置两次吗？

**是的**，因为每个环境使用不同的 VM：
- `make setup-wif` → 选择 production → 配置生产 VM
- `make setup-wif` → 选择 development → 配置测试 VM

Service Account 和 Workload Identity Pool 是共享的，只会创建一次。

### Q: 我只有一台 VM，怎么办？

可以先用单环境模式：
1. 只创建 `production` 环境
2. 只用 `main` 分支
3. 手动测试后再部署

等有第二台 VM 时再配置 `development` 环境。

---

## ✅ 配置检查清单

### 本地

- [ ] 创建了 `.env.production` 文件
- [ ] 创建了 `.env.development` 文件
- [ ] 配置内容正确且不同

### GitHub

- [ ] 创建了 `production` 环境
- [ ] 创建了 `development` 环境
- [ ] production 环境有所有需要的 Secrets
- [ ] development 环境有所有需要的 Secrets
- [ ] 两个环境的 `GCP_VM_NAME` 不同

### GCP

- [ ] 生产 VM 存在且运行中
- [ ] 测试 VM 存在且运行中
- [ ] 两个 VM 都启用了 OS Login
- [ ] Service Account 有正确的权限

### 测试

- [ ] `git push origin dev` 成功部署到测试 VM
- [ ] `git push origin main` 成功部署到生产 VM
- [ ] 两个 VM 上的服务正常运行
