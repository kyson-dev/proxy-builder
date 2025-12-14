# WIF 配置常见问题解答（FAQ）

## 🤔 关于 setup-wif.sh

### Q1: Service Account 会被重复创建吗？

**A:** 不会。脚本有完善的检查机制：

```bash
# 脚本会先检查 Service Account 是否存在
if ! gcloud iam service-accounts describe "$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com" --project "$PROJECT_ID" &>/dev/null; then
    # 不存在才创建
    gcloud iam service-accounts create "$SA_NAME" ...
else
    echo "Service Account already exists, skipping creation."
fi
```

**同样的检查也适用于：**
- ✅ Workload Identity Pool（如已存在则跳过）
- ✅ Workload Identity Provider（如已存在则跳过）

**这意味着：**
- 可以安全地多次运行 `make setup-wif`
- 不会创建重复的资源
- 只会更新 GitHub Secrets

---

### Q2: VM_NAME 和 VM_ZONE 可以跳过吗？

**A:** 不可以，这两个字段现在是**必填项**。

**原因：**
- `deploy.yml` 需要这两个值来构建 SSH 主机名
- 没有它们，GitHub Actions 无法连接到 VM
- 部署会失败

**脚本的改进：**

1. **VM_NAME 必填且会验证**
   ```bash
   # 脚本会验证 VM 是否存在
   if gcloud compute instances describe "$VM_NAME" --project "$PROJECT_ID" &>/dev/null; then
       echo "✅ VM '$VM_NAME' found"
       # 自动检测 Zone
       DETECTED_ZONE=$(gcloud compute instances list --filter="name=$VM_NAME" --format="value(zone)")
   else
       echo "⚠️  VM '$VM_NAME' not found"
       # 询问是否继续
   fi
   ```

2. **VM_ZONE 可以自动检测**
   - 如果 VM 存在，脚本会自动检测它的 Zone
   - 您只需按回车确认即可

3. **自动检查 OS Login**
   - 脚本会检查 VM 是否启用了 OS Login
   - 如果没有启用，会询问是否自动启用
   - OS Login 是 WIF SSH 连接的必要条件

---

### Q3: 如果我的 VM 还没创建怎么办？

**A:** 有两种方案：

**方案 1：先创建 VM（推荐）**
```bash
# 创建一个简单的 VM
gcloud compute instances create YOUR_VM_NAME \
  --zone=us-central1-a \
  --machine-type=e2-medium \
  --metadata=enable-oslogin=TRUE
```

然后运行 `make setup-wif`

**方案 2：先配置 WIF，后创建 VM**
1. 运行 `make setup-wif` 时输入计划使用的 VM 名称
2. 当脚本提示 "VM not found" 时，选择 "y" 继续
3. 手动输入 Zone
4. 创建 VM 后，确保启用 OS Login：
   ```bash
   gcloud compute instances add-metadata YOUR_VM_NAME \
     --zone=YOUR_VM_ZONE \
     --metadata enable-oslogin=TRUE
   ```

---

### Q4: 如果我想更换 VM 怎么办？

**A:** 只需更新 GitHub Secrets：

```bash
# 方法 1: 重新运行配置脚本（会覆盖所有 Secrets）
make setup-wif

# 方法 2: 只更新 VM 相关的 Secrets
gh secret set GCP_VM_NAME --body "new-vm-name"
gh secret set GCP_VM_ZONE --body "new-vm-zone"
```

确保新 VM 已启用 OS Login：
```bash
gcloud compute instances add-metadata new-vm-name \
  --zone=new-vm-zone \
  --metadata enable-oslogin=TRUE
```

---

## 🔐 关于 OS Login

### Q5: 什么是 OS Login？为什么需要它？

**A:** OS Login 是 GCP 的一项功能，允许使用 IAM 权限管理 SSH 访问。

**传统 SSH 方式：**
- ❌ 需要手动管理 SSH 密钥
- ❌ 密钥可能泄露
- ❌ 难以审计谁访问了 VM

**OS Login 方式：**
- ✅ 使用 Service Account 自动生成临时 SSH 密钥
- ✅ 通过 IAM 权限控制访问
- ✅ 完整的审计日志
- ✅ 密钥自动轮换

**WIF + OS Login 的工作流程：**
```
GitHub Actions 
  → 使用 WIF 获取 GCP 凭证
  → 使用 Service Account 身份
  → 通过 OS Login 生成临时 SSH 密钥
  → 连接到 VM
```

---

### Q6: 如何验证 OS Login 是否启用？

**A:** 运行以下命令：

```bash
gcloud compute instances describe YOUR_VM_NAME \
  --zone=YOUR_VM_ZONE \
  --format="get(metadata.items[key=enable-oslogin].value)"
```

**应该返回：** `TRUE`

**如果返回空或 FALSE，启用它：**
```bash
gcloud compute instances add-metadata YOUR_VM_NAME \
  --zone=YOUR_VM_ZONE \
  --metadata enable-oslogin=TRUE
```

---

## 🔑 关于 GitHub Secrets

### Q7: 为什么有 6 个 Secrets？

**A:** 每个 Secret 都有特定用途：

| Secret | 用途 | 设置方式 |
|--------|------|---------|
| `GCP_PROJECT_ID` | 指定 GCP 项目 | 自动 ✅ |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | WIF 认证 | 自动 ✅ |
| `GCP_SERVICE_ACCOUNT` | WIF 认证 | 自动 ✅ |
| `GCP_VM_NAME` | SSH 连接 | 自动 ✅ |
| `GCP_VM_ZONE` | SSH 连接 | 自动 ✅ |
| `ENV_FILE` | 应用配置 | 手动（`make push-env`） |

**前 5 个由 `make setup-wif` 自动设置**  
**第 6 个需要运行 `make push-env`**

---

### Q8: ENV_FILE 为什么不能自动设置？

**A:** 因为 `.env` 文件在 `.gitignore` 中，不会被提交到仓库。

**安全考虑：**
- `.env` 包含敏感信息（密码、密钥等）
- 不应该提交到 Git
- 需要从本地手动上传

**正确的做法：**
```bash
# 1. 在本地编辑 .env 文件
vim .env

# 2. 上传到 GitHub Secrets
make push-env

# 3. .env 文件保留在本地，不提交到 Git
```

---

## 🚀 关于部署流程

### Q9: deploy.yml 是如何使用这些 Secrets 的？

**A:** 工作流程如下：

```yaml
# 1. 使用 WIF 认证到 GCP
- name: Authenticate to Google Cloud
  uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
    service_account: ${{ secrets.GCP_SERVICE_ACCOUNT }}

# 2. 配置 SSH（使用 OS Login）
- name: Configure SSH
  run: |
    gcloud compute config-ssh --project=${{ secrets.GCP_PROJECT_ID }}
    # 构建 SSH 主机名：VM_NAME.VM_ZONE.PROJECT_ID
    HOST="${{ secrets.GCP_VM_NAME }}.${{ secrets.GCP_VM_ZONE }}.${{ secrets.GCP_PROJECT_ID }}"

# 3. 同步文件
- name: Sync files
  run: |
    rsync -avz ./ ${{ env.VM_HOST }}:~/app/

# 4. 创建 .env 文件
- name: Create .env
  run: |
    ssh ${{ env.VM_HOST }} "cat > ~/app/.env << 'EOF'
    ${{ secrets.ENV_FILE }}
    EOF"

# 5. 执行部署
- name: Deploy
  run: |
    ssh ${{ env.VM_HOST }} "cd ~/app && ./deploy.sh"
```

---

### Q10: 部署失败怎么办？

**A:** 按以下步骤排查：

（...保留原有内容...）

**5. 手动测试 SSH 连接**
```bash
# 在本地测试
gcloud compute ssh YOUR_VM_NAME --zone=YOUR_VM_ZONE
```

---

## 👤 关于用户和权限

### Q11: WIF 部署会在 VM 上创建新用户吗？

**A:** **是的**。

并不是使用您现有的个人账号（如 `kyson`），GCP 会根据 Service Account 自动创建一个系统用户。

**特点：**
- 用户名格式通常为 `sa_12345...` 或 `github_deploy_...`
- 拥有独立的 `/home/sa_xxxxx/` 目录
- **注意：** 默认情况下，该用户可能没有 `docker` 权限。

**解决方案：**
在 `setup-wif.sh` 中，我们建议将权限升级为 `roles/compute.osAdminLogin`（管理员登录），这样该用户就拥有 sudo 权限，可以顺利执行 docker 命令。如果您的脚本使用 `sudo docker` 或您通过 startup script 将其加入了 docker 组，则可以直接使用。

---

## 📊 总结

### 改进后的优势

| 特性 | 改进前 | 改进后 |
|------|--------|--------|
| Service Account | 可能重复创建 | ✅ 自动检查，不重复 |
| VM_NAME/VM_ZONE | 可选（会导致部署失败） | ✅ 必填且验证 |
| VM Zone 检测 | 手动输入 | ✅ 自动检测 |
| OS Login 检查 | 无 | ✅ 自动检查并提示启用 |
| 错误提示 | 简单 | ✅ 详细的错误信息和解决方案 |
| 幂等性 | 部分 | ✅ 完全幂等，可多次运行 |

### 快速命令参考

```bash
# 配置 WIF（一次性，可多次运行）
make setup-wif

# 上传环境变量（每次 .env 更新后）
make push-env

# 触发部署
git push origin main

# 检查 VM OS Login
gcloud compute instances describe VM_NAME --zone=VM_ZONE \
  --format="get(metadata.items[key=enable-oslogin].value)"

# 启用 OS Login
gcloud compute instances add-metadata VM_NAME --zone=VM_ZONE \
  --metadata enable-oslogin=TRUE

# 查看 Service Account
gcloud iam service-accounts list

# 查看 GitHub Secrets
gh secret list
```
