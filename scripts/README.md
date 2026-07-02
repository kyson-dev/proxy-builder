# Scripts 目录结构说明

本目录按**生命周期阶段**组织所有脚本，每个阶段对应一个子目录。

## 目录结构

```
scripts/
│
├── lib/                              # 共享库（被 source，不独立执行）
│   ├── common.sh                     # 通用函数：颜色/日志/错误处理/重试
│   ├── paths.sh                      # 全局路径常量（Single Source of Truth）
│   ├── prompt.sh                     # 交互式提示函数（仅 setup 阶段使用）
│   ├── gcp.sh                        # GCP 操作封装（gcloud CLI）
│   ├── docker.sh                     # Docker 工具函数
│   └── os.sh                         # OS 检测与包管理抽象（仅 provision 阶段使用）
│
├── setup/                            # 一次性基础设施配置（本地运行，交互式）
│   │                                 # 执行频率：新环境或基础设施变更时
│   ├── setup-wif.sh                  # [入口] WIF 全流程编排（12 步）
│   ├── upload-env.sh                 # [入口] 上传 .env 到 GitHub Secrets
│   ├── setup-firewall.sh             # [入口] 配置 GCP 防火墙规则
│   └── wif/                          # setup-wif.sh 的子模块
│       ├── select-environment.sh     # Step 0: 选择目标环境
│       ├── select-project.sh         # Step 1: 选择 GCP 项目
│       ├── confirm-repo.sh           # Step 2: 确认 GitHub 仓库
│       ├── enable-apis.sh            # Step 3: 启用 GCP APIs
│       ├── setup-service-account.sh  # Step 4-5: 创建 SA 并授权
│       ├── setup-wif-pool.sh         # Step 6-7: 创建 WIF Pool/Provider
│       ├── bind-repo-to-sa.sh        # Step 8: 绑定仓库到 SA
│       ├── select-vm.sh              # Step 9: 选择 VM
│       ├── create-vm.sh              # Step 9: 创建 VM（含防火墙规则）
│       ├── ensure-oslogin.sh         # Step 10: 确保 OS Login 启用
│       ├── setup-artifact-registry.sh # Step 10.5: 配置 Artifact Registry
│       └── set-github-secrets.sh     # Step 11: 写入 GitHub Secrets
│
├── provision/                        # 主机系统级初始化（远程 VM 运行，自动化）
│   │                                 # 执行频率：新 VM 或系统环境变更时（幂等）
│   ├── provision.sh                  # [入口] 供给编排
│   ├── install-dependencies.sh       # 安装 jq、openssl
│   ├── install-docker.sh             # 安装 Docker CE + Compose
│   ├── enable-bbr.sh                 # 启用 BBR TCP 拥塞控制
│   ├── configure-journald.sh         # 限制 journald 日志容量为 500M
│   ├── configure-ops-agent.sh        # 安装并配置 Google Cloud Ops Agent
│   ├── configure-permission.sh       # 初始化 /opt/proxy 工作目录权限
│   └── check-host-env.sh             # 诊断工具：检查主机供给状态
│
└── deploy/                           # 应用层部署（远程 VM 运行，自动化）
    │                                 # 执行频率：每次代码变更时（幂等）
    ├── deploy.sh                     # [入口] 部署编排
    ├── deploy-on-host.sh             # [CI 入口] VM 端完整部署流程（含回滚）
    ├── validate-env.sh               # 校验必填环境变量
    ├── init-env.sh                   # 初始化环境配置（补充默认值）
    ├── init-data-dir.sh              # 创建持久化数据目录
    ├── generate-certs.sh             # 生成自签名 TLS 证书
    ├── build-config.sh               # 构建 sing-box config.json
    ├── start-services.sh             # 拉取镜像并启动 Docker Compose
    └── health-check.sh               # 服务健康检查与订阅链接输出
```

## 分类原则

### 生命周期阶段（目录分组的主轴）

| 阶段 | 目录 | 执行环境 | 交互模式 | 执行频率 |
|------|------|---------|---------|---------|
| Setup | `setup/` | 本地开发机 | 交互式 | 一次性 |
| Provision | `provision/` | 远程 VM（root） | 自动化 | 幂等，按需 |
| Deploy | `deploy/` | 远程 VM | 自动化 | 每次部署 |

交互模式与执行环境强相关：Setup 在本地运行因此是交互式，Provision/Deploy 由 CI 远程调用因此是自动化。两者不需要独立的目录分隔维度。

### 代码角色

| 角色 | 标识 | 说明 |
|------|------|------|
| 入口脚本 | `[入口]` / `[CI 入口]` | 编排子模块的顶层脚本，定义执行流程 |
| 子模块 | `wif/` 下各文件 | 单一职责的功能单元，被入口 source 调用 |
| 库 | `lib/` | 纯函数/常量，不独立执行，被多方 source |

## 使用方法

### Setup 阶段（本地运行）

```bash
# WIF 配置（首次建立 CI/CD 环境时）
make setup-wif
# 等价于: ./scripts/setup/setup-wif.sh

# 上传 .env 到 GitHub Secrets
make upload-env

# 配置防火墙规则
make setup-firewall
```

### CI/CD 自动触发

GitHub Actions workflow (`deploy.yml`) 通过 WIF 认证后：
1. 构建并推送 subscription 镜像到 Artifact Registry
2. 打包 `scripts/` + 配置文件传输到 VM
3. 远程调用 `scripts/deploy/deploy-on-host.sh`

`deploy-on-host.sh` 内部按需自动调用：
- `scripts/provision/check-host-env.sh` — 诊断主机状态
- `scripts/provision/provision.sh` — 主机未就绪时自举（需 sudo）
- `scripts/deploy/deploy.sh` — 应用层部署

## 库函数说明

### common.sh — 通用函数

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

### prompt.sh — 交互式提示（仅 setup 阶段）

```bash
select_from_list "提示" "选项1" "选项2"
echo $SELECTED_VALUE

select_with_default "提示" "默认值" "选项1" "选项2"

if confirm "是否继续?"; then
    echo "用户确认"
fi

prompt_with_default "名称" "默认值"
prompt_required "必填项"
```

### gcp.sh — GCP 相关

```bash
gcp_get_current_project
gcp_list_projects
gcp_select_project          # 交互式选择
gcp_create_sa "sa-name" "project-id"
gcp_create_wif_pool "pool-name" "project-id"
gcp_list_vms "project-id"
```

### os.sh — 操作系统（仅 provision 阶段）

```bash
detect_os                    # 检测 OS，设置 OS_ID, PKG_MANAGER
pkg_install "pkg1" "pkg2"
pkg_installed "package"
service_is_running "docker"
service_start "docker"
service_enable "docker"
```

## 设计约定

1. **幂等性** — 所有 `provision/` 和 `deploy/` 子模块实现 `is_*_ready()` 检测函数，已就绪则跳过
2. **防重复加载** — 所有 `lib/` 文件用 `_LIB_*_LOADED` 守卫变量防止重复 source
3. **变量隔离** — 子模块临时变量用 `local`，通过全局变量（如 `PROJECT_ID`、`VM_NAME`）向主脚本输出结果
4. **独立运行支持** — 子模块通过 `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` 检测直接执行场景，在该场景下自行加载依赖库（用 `_SELF_DIR` 避免污染主脚本的 `SCRIPT_DIR`）
5. **路径单一数据源** — `lib/paths.sh` 集中定义 `/opt/proxy` 等远程主机路径，deploy.yml 通过 `source scripts/lib/paths.sh` 引用
