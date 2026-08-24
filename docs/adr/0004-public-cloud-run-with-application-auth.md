# 0004. 公开 Cloud Run 入口并由应用认证订阅用户

**状态：** Accepted  
**日期：** 2026-08-24  
**影响：** Cloud Run、订阅 HTTP API、OpenTofu、客户端配置

## 背景

订阅服务迁移到 Cloud Run 后存在两种认证边界：Cloud Run Invoker IAM 可以认证 Google 身份，应用的 `subscription_token` 可以认证代理用户。sing-box、Clash 等订阅客户端不会获取或刷新 Google ID Token，因此启用 Invoker IAM 会使正常订阅请求在到达应用前失败。

GitHub WIF 和 Cloud Run runtime Service Account 分别保护部署与 GCP 资源访问，不负责认证订阅用户。

## 决定

Cloud Run subscription 服务使用公开 ingress、启用默认 `run.app` URL，并设置 `invoker_iam_disabled = true`。不再为 `allUsers` 维护 `roles/run.invoker` binding。

`/healthz` 公开；`/v1/subscription` 由应用按用户的高熵 `subscription_token` 认证。token 继续放在 query parameter 以兼容订阅客户端。

## 理由

公开 Cloud Run 只允许请求抵达应用，不等于公开订阅内容。应用 token 能被现有客户端直接使用，并支持逐用户禁用和轮换；Google 身份认证无法提供这些客户端能力。单一公开机制也避免 Invoker IAM 与 `allUsers` binding 漂移。

## 未采用方案

| 方案 | 未采用原因 |
| --- | --- |
| 要求 Cloud Run Google ID Token | 代理订阅客户端不能登录 Google 或自动刷新身份 |
| 保留 `allUsers roles/run.invoker` | 与禁用 Invoker IAM 重复，产生两套公开状态 |
| 删除应用 token | 知道 URL 的任何人都可取得用户代理凭据 |
| 只支持 Authorization header | 部分订阅客户端只能保存包含 query token 的 URL |

## 后果

- 网络上的任何调用者都能访问 `/healthz` 并向订阅路径发送请求。
- 缺少、无效或已禁用用户的 token 必须继续分别被应用拒绝。
- Cloud Run 自动 request log 必须按精确服务名排除，避免 query token 持久化；应用日志保留脱敏事件。
- 若未来要求 Cloud Run IAM，必须先设计客户端身份获取与刷新流程，并用新 ADR 取代本决定。

## 关联

- Architecture：[overview.md](../architecture/overview.md)
- Design：[订阅服务](../design/subscription-service.md)、[基础设施与身份](../design/infrastructure-and-identity.md)
- 前序决策：[ADR-0002](0002-separate-proxy-and-subscription-runtimes.md)、[ADR-0003](0003-own-and-deliver-application-secrets.md)
