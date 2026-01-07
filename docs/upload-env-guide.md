# 环境变量上传到 GitHub 使用指南

## 📋 概述

这个脚本会读取本地的 `.env` 文件，并将其中的环境变量上传到 GitHub Environment Secrets，用于 GitHub Actions 自动部署。

## 🚀 快速开始

### 1. 准备工作

```bash
# 安装 GitHub CLI（如果还没安装）
brew install gh

# 登录 GitHub
gh auth login
```

### 2. 创建配置文件

```bash
# 复制模板
cp .env.example .env

# 编辑配置
nano .env
```

在 `.env` 中设置：
```bash
PANEL_DOMAIN=panel.example.com
# 可以添加其他环境变量
```

### 3. 上传到 GitHub

```bash
# 方式 1: 使用 Makefile（推荐）
make upload-env

# 方式 2: 直接运行脚本
./scripts/upload-env.sh

# 方式 3: 指定仓库和环境
./scripts/upload-env.sh kysonzou/proxy-builder production
```

## 📖 详细说明

### 命令参数

```bash
./scripts/upload-env.sh [owner/repo] [environment]
```

- `owner/repo` - GitHub 仓库（可选，自动检测）
- `environment` - 环境名称（可选，默认: production）

### 示例

```bash
# 自动检测仓库，使用 production 环境
./scripts/upload-env.sh

# 指定仓库，使用 production 环境
./scripts/upload-env.sh kysonzou/proxy-builder

# 指定仓库和 development 环境
./scripts/upload-env.sh kysonzou/proxy-builder development
```

## 🔍 工作流程

```
1. 读取 .env 文件
   ↓
2. 解析环境变量（跳过注释和空行）
   ↓
3. 使用 gh CLI 上传到 GitHub Secrets
   ↓
4. 显示上传结果
```

## ⚙️ .env 文件格式

```bash
# 这是注释，会被跳过

# 面板域名
PANEL_DOMAIN=panel.example.com

# 其他配置
# DATA_ROOT=/custom/path
```

**规则：**
- ✅ 支持注释（`#` 开头）
- ✅ 支持空行
- ✅ 自动去除前后空格
- ❌ 跳过空值的变量

## 🎯 GitHub Environment 设置

### 创建 Environment

1. 访问仓库设置：`https://github.com/owner/repo/settings/environments`
2. 点击 "New environment"
3. 输入环境名称（如 `production`）
4. 保存

### 查看 Secrets

上传后，可以在以下位置查看：
```
Settings → Environments → [环境名] → Environment secrets
```

## 🔐 安全说明

- ✅ `.env` 文件已在 `.gitignore` 中，不会提交到 Git
- ✅ GitHub Secrets 是加密存储的
- ✅ 只有有权限的人才能查看和修改
- ⚠️ 不要在公开场合分享 `.env` 文件

## 📊 输出示例

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
上传环境变量到 GitHub Secrets
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   自动检测到仓库: kysonzou/proxy-builder
   使用默认环境: production

📝 从 .env 读取配置
   上传: PANEL_DOMAIN
   ✓ PANEL_DOMAIN

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ 上传完成
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📊 统计:
   成功: 1
   跳过: 0

📋 环境: production
📦 仓库: kysonzou/proxy-builder

🔗 查看 Secrets:
   https://github.com/kysonzou/proxy-builder/settings/environments
```

## ❓ 常见问题

### Q: 提示 "GitHub CLI (gh) 未安装"？

```bash
# macOS
brew install gh

# Linux
# 参考: https://github.com/cli/cli#installation
```

### Q: 提示 "未登录 GitHub CLI"？

```bash
gh auth login
# 按提示完成登录
```

### Q: 如何验证上传成功？

访问：`https://github.com/owner/repo/settings/environments`

查看对应环境的 Secrets 列表。

### Q: 可以上传多个环境吗？

可以！分别上传到不同的环境：

```bash
# 上传到 production
./scripts/upload-env.sh kysonzou/proxy-builder production

# 上传到 development
./scripts/upload-env.sh kysonzou/proxy-builder development
```

### Q: 如何更新已存在的 Secret？

直接再次运行脚本即可，会自动覆盖旧值。

## 🔄 完整工作流

```bash
# 1. 创建配置
cp .env.example .env
nano .env  # 编辑配置

# 2. 上传到 GitHub
make upload-env

# 3. 推送代码触发部署
git push origin main

# 4. GitHub Actions 会自动使用这些环境变量进行部署
```

## 📚 相关文档

- [GitHub CLI 文档](https://cli.github.com/manual/)
- [GitHub Environments](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment)
- [GitHub Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
