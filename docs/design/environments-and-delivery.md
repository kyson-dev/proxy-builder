# 环境与交付

本文唯一拥有环境配置归属、GitHub Variables/Secrets 名称、工作流接口以及 VM 与 Cloud Run 的发布协议。

**实现状态：** 环境清单、release bundle 与 host 部署组件已实现并离线验证；GitHub 工作流与 GCP 交付尚未实现。

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
| Reality 伪装目标、HY2 SNI、sing-box image digest | `config/environments/<environment>.json` | 否 |
| WIF provider 和 plan/apply/deploy SA 地址 | GitHub Variables | 否 |
| 应用私钥、密码、证书、用户 | GitHub Environment Secrets | 是 |
| Cloud Run 当前用户与混淆密码 secret version | Secret Manager | 是，运行时副本 |
| VM 当前运行秘密 | VM 限权目录 | 是，运行时副本 |

同一个值不得同时由本地 `.env`、GitHub 和版本库手工维护。重构完成后删除 `.env.<environment>` 与 `users.<environment>.json` 约定。

`config/environments/<environment>.json` 格式为：

```json
{
  "reality_dest": "www.example.com:443",
  "hy2_sni": "www.example.com",
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

## 工作流接口

### `infra-plan.yml`

- 触发：PR 修改 `infra/**`、环境清单或 provider lock file。
- 对 development 与 production 分别执行 format、validate、静态安全检查和只读 plan。
- 使用 `github-plan`；不得引用 GitHub Environment Secrets。
- 输出经过脱敏的 plan artifact 和 PR summary，不得输出 state 或 secret payload。

### `infra-apply.yml`

- 触发：`workflow_dispatch`。
- 输入：`environment`，枚举为 `development|production`；`stack`，枚举为 `bootstrap|platform`。
- 重新生成 plan 后 apply，不接受其他 workflow 上传的 plan 文件。
- 使用选定 GitHub Environment 的 `github-apply` 身份；production 必须审批。

### `deploy.yml`

- 触发：`workflow_dispatch`。
- 输入：`environment` 与 `git_ref`；production 的 `git_ref` 必须解析为 `main` 可达 commit。
- 构建 subscription 镜像并以 commit SHA 标记，推送后只使用 registry 返回的 digest。
- 顺序：验证输入 → 发布并验证 proxy VM → 写入用户与混淆密码 secret version → 更新并验证 Cloud Run revision。
- 使用 `github-deploy`；不得创建或修改 OpenTofu 拥有的网络、IAM、VM 或 secret 容器。

### `destroy.yml`

- 触发：`workflow_dispatch`。
- 输入：`environment`、`stack`（固定为 `platform`）和 `confirm_project_id`。
- `confirm_project_id` 必须与环境清单完全一致；production 必须审批。
- 不接受 `stack=bootstrap`；不提供删除 GCP Project、Billing、state bucket 或 bootstrap WIF 的路径。

所有第三方 Actions 必须固定到完整 commit SHA。workflow 顶层默认 `contents: read`，每个 job 只增加所需权限；使用 WIF 的 job 才能获得 `id-token: write`。

## VM 发布协议

普通 release bundle 与 host 接口由[代理 VM 运行时](proxy-vm-runtime.md)拥有。调用方必须使用以下发布身份：

```text
release_id    = <40-char-git-sha>-<github-run-id>-<run-attempt>
deployment_id = <github-run-id>-<run-attempt>
```

秘密不进入 bundle。部署 job 通过 IAP 加密通道单独写入 VM staging 文件，权限为 `0600`；主机脚本校验后生成运行配置，成功或失败都删除 staging 文件。

每次部署都经 staging 传输 `REALITY_PRIVATE_KEY`、`OBFS_PASSWORD` 与 `PROXY_USERS_JSON`。`HY2_CERT_PEM`/`HY2_KEY_PEM` 只在按需时传输：部署 job 先比对 VM 当前 certificate fingerprint 与 GitHub Secret 的派生值，缺失或不一致才写入证书对。首次发布时 certificate/key 必须存在；只传一个文件必须失败。

host bootstrap 版本不一致、任何输入校验失败或 `sing-box check` 失败时，job 必须在 VM current 未改变的情况下停止。退出码 `20` 表示新 release 失败但回滚成功；`21` 表示回滚也失败，workflow 必须把后者升级为环境故障。

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

以上全部字段由部署 job 拥有，platform 的 OpenTofu 定义必须对它们声明 `lifecycle { ignore_changes }`，详见[基础设施与身份](infrastructure-and-identity.md)；platform apply 不得覆盖这些字段。

Cloud Run 健康检查失败时，不把流量迁移到新 revision；VM 已发布版本保持有效。Secret version 创建成功但 revision 失败时允许保留该 version 供审计和重试。

**Needs test coverage:** production deploy 必须拒绝不属于 `main` 的 commit，因为工作流仍可能成功部署一个合法但未经 promotion 的镜像。

**Needs test coverage:** 发布日志和 artifact 不包含五个 GitHub Secret 的原文，因为部署成功不会暴露这类静默泄漏。

**Needs test coverage:** VM 在 `secrets/` 为空（首次发布或销毁重建后）时，部署 job 必须判定指纹不一致并写入证书和私钥，因为跳过条件写反会让重建后的 VM 永久拿不到证书。

## 公共命令

```text
make bootstrap ENV=development|production
make validate
make infra-plan ENV=<environment> [STACK=bootstrap|platform]
make infra-apply ENV=<environment> [STACK=bootstrap|platform]
make deploy ENV=<environment> [GIT_REF=<ref>]
make destroy ENV=<environment> STACK=platform
```

命令只作为稳定入口；具体执行步骤在实现后进入 Runbook。

## 关联

- Architecture：[overview.md](../architecture/overview.md)
- ADR：[ADR-0001](../adr/0001-manage-gcp-with-opentofu.md)、[ADR-0003](../adr/0003-own-and-deliver-application-secrets.md)
- Design：[基础设施与身份](infrastructure-and-identity.md)、[共享契约](proxy-and-subscription-contracts.md)、[代理 VM 运行时](proxy-vm-runtime.md)、[订阅服务](subscription-service.md)
