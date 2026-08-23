# 当前架构

本文描述重构开始前仍在运行的系统。已接受但尚未实现的目标位于 [ADR](../adr/README.md) 和 [Design](../design/README.md)。

## 目的与边界

Proxy Builder 在 GCP Compute Engine 上运行 sing-box，为每个用户提供 VLESS Reality TCP 和 Hysteria2 UDP 代理，并通过 HTTP 订阅服务生成客户端配置。

仓库负责 GCP 项目内的部署资源、主机配置和应用发布。GCP Project、Billing、域名与 DNS 位于仓库边界之外。

## 环境

系统有 `development` 与 `production` 两个环境。每个环境使用独立的 GCP Project、WIF Provider、部署 Service Account、VM、代理密钥和用户集合；两者使用相同的区域和资源结构。

GitHub 同名 Environment 保存 GCP 接入参数与应用配置。仓库根目录的 `.env.development`、`.env.production` 和 `users.<environment>.json` 是本地维护副本，脚本可将其上传为 GitHub Environment Secrets。

## 组件与数据流

```text
维护者
  │ workflow_dispatch
  ▼
GitHub Actions ──OIDC/WIF──> GCP deploy Service Account
  │                            │
  ├── build/push ─────────────> Artifact Registry
  └── gcloud scp/ssh ─────────> Compute Engine VM
                                  │
                                  └── Docker Compose
                                      ├── sing-box : TCP/UDP 443
                                      └── subscription : TCP 8080
```

### GitHub Actions

`.github/workflows/deploy.yml` 手动构建订阅服务镜像、推送 Artifact Registry，并把配置、用户文件、Compose 文件和脚本打包上传到 VM。`main` 分支映射到 `production`，其他分支映射到 `development`。

`.github/workflows/deploy-backup-vm.yml` 可在发布过程中创建或复用一台应急 VM，然后执行相同的构建与部署过程。

### GCP 身份与资源

每个环境的 GitHub OIDC 身份通过 WIF 模拟一个部署 Service Account。该账号同时承担 VM、OS Login、Artifact Registry、Storage 和 Service Account 使用相关操作。

基础设施没有声明式 state。`scripts/setup/` 中的 Bash 脚本通过 `gcloud` 创建或更新 WIF、VM、Artifact Registry 和防火墙资源。

### 代理 VM

VM 由 `scripts/provision/` 安装 Docker、启用 BBR 并配置主机。部署脚本生成 sing-box 配置和自签证书，然后启动 Docker Compose。

`sing-box` 容器监听公网 TCP/UDP 443。它从宿主机挂载生成的配置和证书。

`subscription` 容器监听公网 TCP 8080。它读取同一台 VM 上的用户文件和证书，根据请求 token 生成订阅内容，并根据 User-Agent 选择输出格式。

## 状态所有权

| 状态 | 当前所有者 |
| --- | --- |
| GCP 资源实际状态 | 各环境 GCP Project；Bash 通过查询后修改 |
| GCP 接入与应用配置 | GitHub Environment Secrets，本地 `.env.<environment>` 有副本 |
| 用户数据 | GitHub `USERS_JSON` Secret，本地 `users.<environment>.json` 有副本 |
| sing-box 运行配置与证书 | VM 文件系统 |
| 订阅镜像 | 各环境 Artifact Registry |
| 部署版本 | Git commit、GitHub run 与 VM 当前文件共同体现 |

## 当前约束

- 环境选择与 Git 分支隐式绑定。
- GitHub Environment 未配置审批或部署分支保护。
- 非敏感 GCP 配置和应用秘密都存为 GitHub Secrets。
- 单一部署身份同时拥有基础设施和应用发布权限。
- 订阅服务、用户文件和证书与代理 VM 共享生命周期。
- GCP 资源缺少可审查的声明式 state，配置来源存在重复。

改变这些边界的原因见 [ADR-0001](../adr/0001-manage-gcp-with-opentofu.md)、[ADR-0002](../adr/0002-separate-proxy-and-subscription-runtimes.md) 和 [ADR-0003](../adr/0003-own-and-deliver-application-secrets.md)。
