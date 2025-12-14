# Scripts 目录结构说明

本目录包含模块化的脚本，用于 WIF 配置和服务部署。

## 目录结构

```
scripts/
├── lib/                          # 通用库函数
│   ├── common.sh                 # 通用函数（颜色、日志、错误处理）
│   ├── prompt.sh                 # 交互式提示函数
│   ├── os.sh                     # 操作系统检测和包管理
│   └── gcp.sh                    # GCP 相关通用函数
│
├── setup-wif/                    # WIF 设置子脚本
│   ├── select-environment.sh     # Step 0: 选择环境
│   ├── select-project.sh         # Step 1: 选择 GCP 项目
│   ├── confirm-repo.sh           # Step 2: 确认 GitHub 仓库
│   ├── enable-apis.sh            # Step 3: 启用 GCP APIs
│   ├── setup-service-account.sh  # Step 4-5: 创建 SA 并授权
│   ├── setup-wif-pool.sh         # Step 6-7: 创建 WIF Pool/Provider
│   ├── bind-repo-to-sa.sh        # Step 8: 绑定仓库到 SA
│   ├── select-vm.sh              # Step 9: 选择 VM
│   ├── create-vm.sh              # Step 9: 创建 VM（含防火墙规则）
│   ├── ensure-oslogin.sh         # Step 10: 确保 OS Login 启用
│   └── set-github-secrets.sh     # Step 11: 设置 GitHub Secrets

│
├── deploy/                       # 部署子脚本
│   ├── enable-bbr.sh             # 启用 BBR 拥塞控制
│   ├── install-docker.sh         # 安装 Docker
│   ├── install-dependencies.sh   # 安装依赖 (openssl, jq)
│   ├── parse-config.sh           # 解析 vars.json 配置
│   ├── configure-firewall.sh     # 配置防火墙规则（根据端口动态创建）
│   ├── generate-certs.sh         # 生成自签名证书
│   ├── start-services.sh         # 启动 Docker Compose 服务
│   └── health-check.sh           # 健康检查
│
└── setup-wif.sh                  # WIF 配置主入口脚本

```

根目录还有：
- `deploy.sh` - 部署主入口脚本

## 使用方法

### 完整流程

```bash
# WIF 配置（本地运行）
./scripts/setup-wif.sh

# 部署服务（在服务器上运行）
./deploy.sh
```

### 单独运行子模块

每个子模块都可以独立运行：

```bash
# 示例：只生成证书
source ./scripts/lib/common.sh
source ./scripts/deploy/generate-certs.sh
generate_certs "./certs" "example.com" 365

# 示例：只检查 Docker
source ./scripts/lib/common.sh
source ./scripts/lib/os.sh
source ./scripts/deploy/install-docker.sh
check_docker
```

## 库函数说明

### common.sh - 通用函数

```bash
# 日志函数
log_info "信息"
log_success "成功"
log_warn "警告"
log_error "错误"
log_step "步骤标题"
log_substep "子步骤"

# 错误处理
die "错误消息"

# 工具函数
command_exists "command"      # 检查命令是否存在
is_root                       # 检查是否 root
ensure_dir "/path"            # 确保目录存在
retry 5 3 "command"           # 重试执行命令
```

### prompt.sh - 交互式提示

```bash
# 选择
select_from_list "提示" "选项1" "选项2"
echo $SELECTED_VALUE

# 带默认值选择
select_with_default "提示" "默认值" "选项1" "选项2"

# 确认
if confirm "是否继续?"; then
    echo "用户确认"
fi

# 输入
prompt_with_default "名称" "默认值"
echo $INPUT_VALUE

prompt_required "必填项"
```

### os.sh - 操作系统相关

```bash
# 检测操作系统
detect_os
echo $OS_ID $PKG_MANAGER

# 包管理
pkg_install "package1" "package2"
pkg_installed "package"

# 服务管理
service_is_running "docker"
service_start "docker"
service_enable "docker"
```

### gcp.sh - GCP 相关

```bash
# 项目管理
gcp_get_current_project
gcp_list_projects
gcp_select_project  # 交互式选择

# Service Account
gcp_create_sa "sa-name" "project-id"
gcp_sa_email "sa-name" "project-id"

# WIF
gcp_create_wif_pool "pool-name" "project-id"
gcp_create_github_provider "provider" "pool" "project" "owner"

# VM
gcp_list_vms "project-id"
gcp_oslogin_enabled "vm" "zone" "project"
```

## 设计原则

1. **模块化** - 每个功能独立成文件，便于维护和测试
2. **可复用** - 通用函数放在 lib/ 下，可被多个脚本使用
3. **防重复加载** - 使用 `_LIB_xxx_LOADED` 变量防止重复 source
4. **可单独运行** - 每个子脚本都可以独立测试
5. **清晰的主脚本** - 主脚本只做编排，逻辑一目了然

## ⚠️ 变量覆盖问题与解决方案

### 问题描述

在 Shell 中，使用 `source` 命令加载文件时，所有变量默认是**全局**的。
如果子模块定义了 `SCRIPT_DIR` 变量，它会覆盖主脚本中同名变量，导致路径错误。

### 解决方案

我们采用以下模式来避免变量覆盖：

**子模块头部模板：**
```bash
#!/bin/bash
# ==============================================================================
# 模块描述
# 注意: 此脚本应被主脚本 source，依赖库由主脚本加载
# ==============================================================================

# 如果直接运行，加载依赖
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_SELF_DIR}/../lib/common.sh"
fi
```

**关键设计：**
1. **主脚本负责加载所有库** - 子模块不再自己 source 库文件
2. **条件加载** - 只有直接运行子模块时才加载依赖（用于独立测试）
3. **使用 `_SELF_DIR` 而非 `SCRIPT_DIR`** - 避免与主脚本的 `SCRIPT_DIR` 冲突
4. **函数内使用 `local`** - 所有临时变量必须用 `local` 修饰

### 数据共享机制

子模块通过**全局变量**与主脚本共享数据：

```bash
# 子模块: select-project.sh
select_gcp_project() {
    local projects  # 局部变量，不污染全局
    # ... 交互逻辑 ...
    
    PROJECT_ID="选中的项目"  # 全局变量，输出给主脚本
    export PROJECT_ID
}

# 主脚本: setup-wif.sh
select_gcp_project           # 调用后，$PROJECT_ID 可用
enable_required_apis "$PROJECT_ID"  # 后续步骤使用
```

