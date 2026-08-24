# 当前架构

本文描述已经在 `development` 激活并验证的系统。`production` 使用同一结构但尚未激活；具体接口位于 [Design](../design/README.md)。

## 目的与边界

Proxy Builder 在 GCP Compute Engine 上运行 sing-box，为每个用户提供 VLESS Reality TCP 和 Hysteria2 UDP 代理，并通过 HTTP 订阅服务生成客户端配置。

仓库负责 GCP 项目内的部署资源、主机配置和应用发布。GCP Project、Billing、域名与 DNS 位于仓库边界之外。

## 环境

系统定义 `development` 与 `production` 两个环境。每个环境使用独立的 GCP Project、OpenTofu state、WIF Provider、Service Accounts、运行资源、代理密钥和用户集合。当前只有 `development` 在线。

GitHub Repository Variables 保存 pull-request plan 身份；同名 GitHub Environment 保存 apply/deploy 身份与五项应用 Secrets。本地 `.secrets/<environment>/` 是权限受限的灾难恢复副本，不进入 Git。

## 组件与数据流

```text
维护者
  │ workflow_dispatch
  ▼
GitHub Actions ──OIDC/WIF──> plan / apply / deploy Service Accounts
  │                              │
  ├── OpenTofu ─────────────────> GCP identity + platform resources
  ├── build/push ───────────────> Artifact Registry
  ├── IAP scp/ssh ──────────────> Compute Engine VM
  │                                └── sing-box : TCP/UDP 443
  └── immutable revision ───────> Cloud Run subscription HTTPS
```

### GitHub Actions

所有可写 workflow 显式接收环境。pull request 使用只读 plan 身份；platform apply 与应用 deploy 使用独立的 GitHub Environment WIF 身份。production 还受 main-only 和人工审批保护。

### GCP 身份与资源

OpenTofu 使用独立 `bootstrap` 与 `platform` state。bootstrap 管理 API、WIF 和 GitHub plan/apply/deploy 身份；platform 管理网络、静态 IP、防火墙、VM、Artifact Registry、Secret Manager 容器、Cloud Run 服务及最小 IAM。

### 代理 VM

VM startup metadata 只负责幂等主机供给。应用部署生成不可变 release，原子切换 `current`，并保留 `previous` 供显式回滚。Docker Compose 中的 sing-box 监听公网 TCP/UDP 443。

订阅服务与 VM 分离，运行在 Cloud Run。默认 HTTPS URL 公开且关闭 Invoker IAM check；`/v1/health` 无需认证，`/v1/subscription` 由逐用户高熵 token 认证。Secret Manager version 以引用方式注入，不把秘密写入 OpenTofu state。

部署先激活 VM，再创建零流量 Cloud Run revision；切流后验证公网健康、两种订阅格式及 VLESS Reality/Hysteria2 真实出站。失败时先恢复旧 Cloud Run traffic，再回滚 VM。

## 状态所有权

| 状态 | 当前所有者 |
| --- | --- |
| GCP 身份与平台资源 | OpenTofu bootstrap/platform state |
| 非秘密 GitHub 接入标识 | Repository / Environment Variables |
| 应用秘密 | GitHub Environment Secrets；本地 `.secrets/<environment>/` 备份 |
| Cloud Run runtime secrets | Secret Manager versions |
| sing-box 配置、证书与 release | VM `/opt/proxy-builder` |
| 应用镜像 | Artifact Registry digest |
| 已部署版本 | Git SHA + GitHub run/attempt + VM release + Cloud Run revision |

## 当前约束

- `development` 已迁移到专用的 `kyson-proxy-dev` Project，并以 `proxy-*` 资源名完成正式发布和双协议 E2E。
- `development` 的 bootstrap/platform plan 当前为零变更，GitHub 配置审计通过。
- `production` 资源与秘密尚未激活，任何写操作仍需显式审批。
- Cloud Run request log 按精确服务名排除，避免 query token 被平台日志持久化；应用仅记录脱敏事件。

改变这些边界的原因见 [ADR-0001](../adr/0001-manage-gcp-with-opentofu.md)、[ADR-0002](../adr/0002-separate-proxy-and-subscription-runtimes.md) 和 [ADR-0003](../adr/0003-own-and-deliver-application-secrets.md)。
