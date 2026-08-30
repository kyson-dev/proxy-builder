# 基础设施与身份

本文唯一拥有 OpenTofu 目录、stack/state 划分、模块接口、GCP 资源拓扑以及 IAM/WIF 边界。

**实现状态：** development 已在 `kyson-proxy-dev` apply、部署并通过零变更 plan；production 目标为 `kyson-proxy-prod`，尚未激活。

## 目录接口

```text
infra/
├── modules/
│   ├── github_identity/
│   ├── network/
│   ├── artifact_registry/
│   ├── proxy_vm/
│   ├── secret_runtime/
│   └── subscription_service/
├── stacks/
│   ├── bootstrap/             独立 root，包含 versions.tf 与 lock file
│   └── platform/              独立 root，包含 versions.tf 与 lock file
└── environments/
    ├── development.tfvars
    └── production.tfvars
```

根模块只组合 modules，不复制资源定义。`development.tfvars` 与 `production.tfvars` 是环境非秘密基础设施输入的唯一来源。

## Backend 与 state

每个环境使用独立 bucket：

```text
<project-id>-proxy-builder-tfstate
```

bucket 必须启用 Object Versioning、Uniform bucket-level access 和 Public access prevention。它由最小 Bash bootstrap 创建，不进入 OpenTofu state。

两个 root stack 使用同一环境 bucket 的独立 prefix：

```text
bootstrap/default.tfstate
platform/default.tfstate
```

本轮不建立 emergency stack；原因见 [ADR-0002](../adr/0002-separate-proxy-and-subscription-runtimes.md)。

backend 的 bucket 与 prefix 由公共命令根据 `ENV` 和 stack 生成，不维护第二份 backend 配置文件。不同 stack 只通过 `terraform_remote_state` 的公开 outputs 交互，不引用彼此内部资源地址。

## 环境变量接口

每个 `*.tfvars` 必须定义：

```hcl
environment        = "development" # 或 production
project_id         = "gcp-project-id"
region             = "asia-northeast3"
zone               = "asia-northeast3-a"
resource_prefix    = "proxy" # 完整资源名前缀，不自动拼接环境
network_cidr       = "10.20.0.0/24"
network_tier       = "STANDARD"
vm_machine_type    = "e2-micro"
vm_boot_disk_gb    = 10
vm_source_image    = "projects/debian-cloud/global/images/debian-12-bookworm-vYYYYMMDD"
artifact_location  = "asia-northeast3"
github_repository  = "owner/repository"
github_repository_id = "immutable numeric repository ID"
labels             = { application = "proxy-builder", environment = "development" }
```

`environment` 只能是 `development` 或 `production`。`labels.application` 与 `labels.environment` 必须应用于支持 label 的所有资源，作为旧资源清理时的归属条件。

`vm_source_image` 必须引用 `debian-cloud` 中带日期的具体 Debian 12 Bookworm 镜像；禁止 image family、`latest`、短名称或动态 data source。修改它会替换单 VM，并因启动盘 `auto_delete` 清除主机上的 current/previous release 与运行秘密。镜像升级必须按 [VM OS 镜像升级](../runbooks/vm-os-image-upgrade.md) 先 development、后 production 独立执行。

`resource_prefix` 是资源 ID 的完整前缀，环境名不参与资源 ID 派生。当前两个环境均为 `proxy`，因此新资源命名为 `proxy-network`、`proxy-vm`、`proxy-subscription`、`proxy-github` 和 `proxy-images`。GitHub 身份为 `proxy-gh-plan`、`proxy-gh-apply`、`proxy-gh-deploy`；运行身份为 `proxy-vm-sa` 与 `proxy-subscription-sa`。Project、GitHub Environment 与 labels 继续承担环境隔离。

名称包含 `_secret`、`password`、`private_key`、`token` 或证书内容的变量禁止进入 OpenTofu 输入。

`existing_static_ip_name` 是可选的 production 迁入接口。未设置时 network 创建并管理 `${resource_prefix}-ipv4`；设置时只读取同项目、同区域的现有静态 IPv4 并将 VM 指向它，不把该地址纳入 OpenTofu state。

## Stack 所有权

### bootstrap

拥有：

- 必需 Project API；
- GitHub WIF pool、单一 GitHub provider 与 attribute mapping；
- `plan`、`apply`、`deploy` Service Account 及最小 IAM；
- GitHub 身份模拟各 Service Account 的绑定。

它不拥有 state bucket、业务网络或运行资源。首次执行使用维护者本地 GCP 身份；完成后常规 plan/apply 通过 WIF。

### platform

拥有：

- 专用 VPC、子网、静态外部 IPv4 和防火墙；
- Artifact Registry repository；
- proxy VM 与 runtime Service Account；
- `proxy-users`、`obfs-password` Secret Manager 容器与 Cloud Run runtime Service Account；
- Cloud Run subscription 服务的区域、公开默认 URL、Invoker IAM 关闭状态和资源限制。

部署工作流拥有 Cloud Run revision 的运行时字段（清单见[环境与交付](environments-and-delivery.md)的 Cloud Run 发布协议）：这些字段来自派生计算或 Secret Manager version，不作为 OpenTofu 变量存在，platform 的 Cloud Run resource 必须对全部这些字段声明 `lifecycle { ignore_changes }`，platform apply 不得覆盖它们。platform 仍然收敛 region、ingress、资源限制、Service Account 和 Secret Manager IAM；Secret 引用随第一个可运行 revision 由 deploy 建立，避免在 secret 尚无 version 时创建无效 revision。

subscription 使用 `INGRESS_TRAFFIC_ALL`、`default_uri_disabled = false` 与 `invoker_iam_disabled = true`。platform 不创建 `allUsers roles/run.invoker` binding；终端用户认证属于[订阅服务](subscription-service.md)的应用 token 接口。

## 模块接口

每个 module 至少接收 `project_id`、`environment`、`resource_prefix` 和 `labels`，只返回消费者需要的稳定值。

platform 必须公开：

```text
proxy_ip_address
proxy_vm_name
proxy_vm_zone
proxy_host_bootstrap_sha256
artifact_repository_url
subscription_service_name
subscription_service_url
subscription_request_log_exclusion_name
proxy_users_secret_id
obfs_password_secret_id
```

输出不得包含 private key、密码、token、证书正文、生成后的 sing-box 配置或 Secret Manager payload。

## Proxy VM startup

`proxy_vm` 通过 instance `metadata` 的 `startup-script` 下发主机供给脚本，并把脚本内容的 SHA-256 写入 `proxy-bootstrap-sha256` metadata。必须使用普通 metadata key，不使用会在内容变化时强制替换 instance 的 `metadata_startup_script` 属性。

脚本更新只产生 metadata 原地变更；运行中 VM 的已执行版本由 `/var/lib/proxy-builder/bootstrap.sha256` 表示。应用发布必须先比较二者并在不一致时拒绝，具体接口由[代理 VM 运行时](proxy-vm-runtime.md)拥有。

startup script 不接收 OpenTofu secret 输入，也不得把应用秘密写入 metadata、serial output 或 state。

## 身份边界

| 身份 | 能力边界 |
| --- | --- |
| `github-plan` | 读取受管资源和 state；获取与释放 state lock；不能修改 GCP 资源 |
| `github-apply` | 修改 bootstrap、platform 两个 OpenTofu stack 声明的资源；Secret Manager 使用不含 `versions.access` 的自定义 metadata/IAM 角色，不能直接读取 payload 或登录 VM |
| `github-deploy` | 读取 platform outputs、推送镜像、增加与清理指定 secret version（`roles/secretmanager.secretVersionManager`，不含读取 payload 的 `secretAccessor`）、更新 Cloud Run revision、通过 IAP/OS Login 发布 VM |
| `proxy-runtime` | 运行 VM；无 Project 级管理角色，无 Secret Manager 读取权限 |
| `subscription-runtime` | 仅读取指定环境的 `proxy-users` 与 `obfs-password` secret |

WIF attribute mapping 必须包含 `repository_id`、`repository_owner_id`、`event_name`、`ref` 和 `sub`。每个环境只有一个 GitHub provider，其 admission condition 使用不可变 repository ID。`github-plan` 绑定精确的 `repo:<owner>/<repo>:pull_request` 与 `repo:<owner>/<repo>:ref:refs/heads/main` subject，分别用于 PR 和 main 的手动只读 plan；`github-apply` 与 `github-deploy` 只绑定精确的 `repo:<owner>/<repo>:environment:<environment>` subject。fork PR 不获得 WIF，GitHub Environment 审批仍是可写身份的必要条件。

subscription token 为客户端兼容性保留在 query parameter。platform 必须按当前环境的 subscription service 名创建 `google_logging_project_exclusion`，仅排除 `run.googleapis.com/requests` 的 Cloud Run 自动 request log，避免其 `requestUrl` 持久化 token；应用自身的脱敏结构化日志继续保留。bootstrap 因此启用 Cloud Logging API，并仅向 `github-apply` 授予 `roles/logging.configWriter`。

## 网络规则

VM ingress 固定为：

| 来源 | 协议/端口 | 目标 |
| --- | --- | --- |
| `0.0.0.0/0` | TCP 443 | proxy VM network tag |
| `0.0.0.0/0` | UDP 443 | proxy VM network tag |
| `35.235.240.0/20` | TCP 22 | proxy VM network tag |

不得创建其他公网 ingress。VM 启用 OS Login，不维护项目级 SSH key metadata。

## 生命周期规则

- 每个 root stack 固定 OpenTofu 与 provider 版本，并提交自己的 `.terraform.lock.hcl`；module 只声明 provider source，不重复版本约束。
- production 不得与 development 共用 bucket、state prefix、Service Account、VPC、静态 IP、secret 或运行资源。
- `platform` 连续两次 apply 的第二次必须为零变更，才算环境收敛。
- destroy 只能作用于一个明确环境，且调用层必须要求输入该环境完整 Project ID。
- Project、Billing、state bucket 和 bootstrap WIF 不属于常规 platform destroy 范围。

## 关联

- Architecture：[overview.md](../architecture/overview.md)
- ADR：[ADR-0001](../adr/0001-manage-gcp-with-opentofu.md)、[ADR-0002](../adr/0002-separate-proxy-and-subscription-runtimes.md)
- Design：[环境与交付](environments-and-delivery.md)、[代理 VM 运行时](proxy-vm-runtime.md)
