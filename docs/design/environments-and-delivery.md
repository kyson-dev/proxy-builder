# 环境与交付

本文唯一拥有环境配置归属、GitHub Variables/Secrets 名称、工作流接口以及 VM 与 Cloud Run 的发布协议。

**实现状态：** 环境清单、发布工具与 GitHub 工作流已实现并离线验证；GitHub/GCP 尚未配置或执行。

## 环境模型

环境名固定为 `development` 与 `production`，同名对象必须在以下位置一一对应：

```text
infra/environments/<environment>.tfvars
GitHub Environment: <environment>
GCP Project: tfvars.project_id
GCS state bucket: <project-id>-proxy-builder-tfstate
```

Git 分支只标识版本，不隐式选择环境。所有可写工作流必须接受显式 `environment` 输入；production 只允许来自 `main` 的 commit，并受 GitHub Environment 审批保护。

## 配置所有权

| 数据 | 权威来源 | 是否秘密 |
| --- | --- | --- |
| Project、region/zone、规格、资源名、网络 | `infra/environments/<environment>.tfvars` | 否 |
| Reality 伪装目标、HY2 SNI、sing-box image digest、E2E 目标 | `config/environments/<environment>.json` | 否 |
| WIF provider 和 plan/apply/deploy SA 地址 | GitHub Variables | 否 |
| 应用私钥、密码、证书、用户 | GitHub Environment Secrets | 是 |
| 应用秘密的灾难恢复副本 | `.secrets/<environment>/` | 是，本地且 Git ignored |
| Cloud Run 当前用户与混淆密码 secret version | Secret Manager | 是，运行时副本 |
| VM 当前运行秘密 | VM 限权目录 | 是，运行时副本 |

`.env` 与仓库根目录的 users 文件不是配置接口。应用秘密只由本地 `.secrets/<environment>/` 生成和维护，再显式发布到 GitHub；本地副本长期保留用于灾难恢复，不参与运行时读取。

`config/environments/<environment>.json` 格式为：

```json
{
  "reality_dest": "www.example.com:443",
  "hy2_sni": "www.example.com",
  "egress_probe_url": "https://example.com/generate_204",
  "sing_box_image": "ghcr.io/sagernet/sing-box@sha256:<digest>"
}
```

## GitHub 配置

Repository Variables 为 PR plan 提供非秘密只读接入标识：

```text
DEV_GCP_WIF_PROVIDER
DEV_GCP_PLAN_SERVICE_ACCOUNT
PROD_GCP_WIF_PROVIDER
PROD_GCP_PLAN_SERVICE_ACCOUNT
```

每个 GitHub Environment Variables 固定为：

```text
GCP_APPLY_SERVICE_ACCOUNT
GCP_DEPLOY_SERVICE_ACCOUNT
```

apply/deploy 根据显式环境复用对应 Repository Variable 中的 WIF provider；provider 标识不在 GitHub Environment 重复保存。

每个 GitHub Environment Secrets 固定为：

```text
REALITY_PRIVATE_KEY
OBFS_PASSWORD
HY2_CERT_PEM
HY2_KEY_PEM
PROXY_USERS_JSON
```

Project ID、region、zone、VM 名、Artifact Registry 名、公钥、short ID、SNI 和伪装目标不得保存为 Secret。

`make github-configure ENV=<environment>` 从已 apply 的 bootstrap state 读取 WIF provider 与三个 service account，并写入以上 GitHub Variables；它不创建身份、不上传应用秘密，也不使用 service-account key。

`make github-reset ENV=development CONFIRM=<owner/repo>:development` 只允许 development：校验不可变 repository ID 后，删除 development Environment 及两项受管 `DEV_` Repository Variables。production 必须拒绝。重建后的 audit 要求对应环境的 Variable/Secret 名称与上述清单精确相等，且四项非秘密 Variable 值与 bootstrap outputs 相等。

## 工作流接口

### `infra-plan.yml`

- 触发：PR 修改 `infra/**`、环境清单或 provider lock file。
- 对 development 与 production 分别执行 format、validate、静态安全检查和只读 plan。
- 使用 `github-plan`；不得引用 GitHub Environment Secrets。
- 输出经过脱敏的 plan artifact 和 PR summary，不得输出 state 或 secret payload。
- fork PR 与缺少 Repository Variables 的仓库安全跳过 WIF plan；所有 PR 仍由 `validate.yml` 执行无凭据验证。

### `infra-apply.yml`

- 触发：`workflow_dispatch`。
- 输入：`environment`，枚举为 `development|production`；`stack`，枚举为 `bootstrap|platform`。
- 重新生成 plan 后 apply，不接受其他 workflow 上传的 plan 文件。
- 使用选定 GitHub Environment 的 `github-apply` 身份；production 必须审批。

### `deploy.yml`

- 触发：`workflow_dispatch`。
- 输入：`environment` 与 `git_ref`；production 的 `git_ref` 必须解析为 `main` 可达 commit。
- 构建 subscription 镜像并以 commit SHA 标记，推送后只使用 registry 返回的 digest。
- 顺序：验证输入 → 发布 proxy VM → 创建无流量 Cloud Run revision 并等待 startup probe → 按不可变 revision name 切流 → 公网 health/订阅复验 → 真实双协议 E2E。
- 使用 `github-deploy`；不得创建或修改 OpenTofu 拥有的网络、IAM、VM 或 secret 容器。

### `destroy.yml`

- 触发：`workflow_dispatch`。
- 输入：`environment`、`stack`（固定为 `platform`）和 `confirm_project_id`。
- `confirm_project_id` 必须与环境清单完全一致；production 必须审批。
- 不接受 `stack=bootstrap`；不提供删除 GCP Project、Billing、state bucket 或 bootstrap WIF 的路径。

所有第三方 Actions 必须固定到完整 commit SHA。workflow 顶层默认 `contents: read`，每个 job 只增加所需权限；使用 WIF 的 job 才能获得 `id-token: write`。

全部可写 workflow 使用 `proxy-builder-<environment>` concurrency group 且不取消运行中的操作。production 还要求 workflow ref 为 `main`、目标 commit 可从 `origin/main` 到达，并且 Repository Variable `PRODUCTION_OPERATIONS_ENABLED` 精确为 `true`；配置脚本只有在环境保护审计通过后才可设置该开关。

## VM 发布协议

普通 release bundle 与 host 接口由[代理 VM 运行时](proxy-vm-runtime.md)拥有。调用方必须使用以下发布身份：

```text
release_id    = <40-char-git-sha>-<github-run-id>-<run-attempt>
deployment_id = <github-run-id>-<run-attempt>
```

秘密不进入 bundle。部署 job 通过 IAP 加密通道单独写入 VM staging 文件，权限为 `0600`；主机脚本校验后生成运行配置，成功或失败都删除 staging 文件。

每次部署都经 staging 传输 `REALITY_PRIVATE_KEY`、`OBFS_PASSWORD` 与 `PROXY_USERS_JSON`。`HY2_CERT_PEM`/`HY2_KEY_PEM` 只在按需时传输：部署 job 先比对 VM 当前 certificate fingerprint 与 GitHub Secret 的派生值，缺失或不一致才写入证书对。首次发布时 certificate/key 必须存在；只传一个文件必须失败。

host bootstrap 版本不一致、任何输入校验失败或 `sing-box check` 失败时，job 必须在 VM current 未改变的情况下停止。退出码 `20` 表示新 release 失败且旧 release 已恢复健康；`21` 表示没有可恢复的旧 release 或旧 release 未恢复健康，workflow 必须把它升级为环境故障。

## Cloud Run 发布协议

部署 job 将经过 schema 校验的 `PROXY_USERS_JSON` 与 `OBFS_PASSWORD` 分别写为指定 secret 的新 version，然后更新 Cloud Run revision：

```text
image = subscription image digest
PROXY_IP = platform.proxy_ip_address
REALITY_PUBLIC_KEY = 从 REALITY_PRIVATE_KEY 派生
REALITY_SHORT_ID = 从环境私钥稳定派生的 8-byte hex 标识
REALITY_DEST = environment config
HY2_SNI = environment config
HY2_CERT_SHA256 = 从 HY2_CERT_PEM 计算
OBFS_PASSWORD = Secret Manager version 引用
PROXY_USERS_JSON = Secret Manager version 引用
```

以上全部字段由部署 job 拥有，platform 的 OpenTofu 定义必须对它们声明 `lifecycle { ignore_changes }`，同时忽略 gcloud 写入的 `client` 与 `client_version` 部署者元数据，详见[基础设施与身份](infrastructure-and-identity.md)；platform apply 不得覆盖这些字段，也不得为清除部署者元数据制造空更新。

Secret version 创建成功但 revision 失败时允许保留该 version 供审计和重试。

候选 revision 必须以 `--no-traffic` 创建，并在每次 deploy 时显式保持 `ingress=all`、关闭 Invoker IAM check、启用默认 URL；只在 platform 创建服务时设置这些字段不足以保证后续 revision 可公开调用。Cloud Run 拥有的 `/v1/health` startup probe 是切流前门禁；deploy 必须读取 `latestCreatedRevisionName`，确认它非空且不同于旧 revision，再直接轮询该 revision 的 Ready condition，最后按该不可变名称切换 100% 流量。部署不得依赖可能滞后的 `latestReadyRevisionName` 或 traffic-tag URL。

切流后必须在有界时间内等待公网 `/v1/health` 成功，以吸收 Cloud Run 边缘流量传播延迟；随后校验 Base64 与 Clash 正文，再从 runner 分别通过订阅中的 VLESS Reality 和 Hysteria2 连接 VM，并访问环境固定的 HTTPS 204 URL。部署是 VM 与 Cloud Run 的协调事务：切流前任一步骤失败，旧 Cloud Run 不变并显式回滚本次 VM release；等待超时、公网复验或任一 E2E 失败，先恢复旧 Cloud Run revision 的 100% 流量，再回滚 VM。两侧恢复都成功时退出 `20`；任一恢复失败时退出 `21` 并要求人工介入。失败 revision 与 secret version 保留供审计。

## 公共命令

```text
make bootstrap ENV=development|production
make secrets-init ENV=<environment> USER=<name>
make github-reset ENV=development CONFIRM=<owner/repo>:development
make github-configure ENV=<environment>
make github-audit ENV=<environment>
make secrets-publish ENV=<environment>
make user-add|user-enable|user-disable|user-rotate ENV=<environment> USER=<name>
make subscription-url ENV=<environment> USER=<name> [FORMAT=base64|clash]
make validate
make infra-plan ENV=<environment> [STACK=bootstrap|platform]
make infra-apply ENV=<environment> [STACK=bootstrap|platform]
make deploy ENV=<environment> [GIT_REF=<ref>]
make destroy ENV=<environment> STACK=platform
```

命令只作为稳定入口；首次 development 激活步骤见 [Runbook](../runbooks/development-first-activation.md)。

`secrets-init` 只在本地新建五项随机秘密，不发布或调用 GCP；已有目录时拒绝覆盖。用户变更也只改本地 `users.json`，必须随后显式执行 `secrets-publish` 和 `deploy`。`subscription-url` 从 platform state 读取公开服务 URL，从本地文件读取已启用用户 token，并只向终端输出最终 URL。

就绪工具中，`proxyctl inspect-environment` 校验五项秘密且只输出公开派生值；`validate-subscription` 严格验证 Base64/Clash；`render-probe-config` 只为部署期真实 E2E 生成临时 sing-box 客户端配置。GitHub 的配置、只读保护审计和五项秘密发布分别由 `configure.sh`、`audit.sh` 与 `publish-secrets.sh` 拥有。

## 关联

- Architecture：[overview.md](../architecture/overview.md)
- ADR：[ADR-0001](../adr/0001-manage-gcp-with-opentofu.md)、[ADR-0003](../adr/0003-own-and-deliver-application-secrets.md)
- Design：[基础设施与身份](infrastructure-and-identity.md)、[共享契约](proxy-and-subscription-contracts.md)、[代理 VM 运行时](proxy-vm-runtime.md)、[订阅服务](subscription-service.md)
