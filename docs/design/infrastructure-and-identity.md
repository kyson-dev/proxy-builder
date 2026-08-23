# 基础设施与身份

本文唯一拥有 OpenTofu 目录、stack/state 划分、模块接口、GCP 资源拓扑以及 IAM/WIF 边界。

**实现状态：** 尚未实现

## 目录接口

```text
infra/
├── versions.tf
├── modules/
│   ├── github_identity/
│   ├── network/
│   ├── artifact_registry/
│   ├── proxy_vm/
│   ├── secret_runtime/
│   └── subscription_service/
├── stacks/
│   ├── bootstrap/
│   └── platform/
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
resource_prefix    = "proxy"
network_cidr       = "10.20.0.0/24"
vm_machine_type    = "e2-micro"
vm_boot_disk_gb    = 10
artifact_location  = "asia-northeast3"
github_repository  = "owner/repository"
github_repository_id = "immutable numeric repository ID"
labels             = { application = "proxy-builder", environment = "development" }
```

`environment` 只能是 `development` 或 `production`。`labels.application` 与 `labels.environment` 必须应用于支持 label 的所有资源，作为旧资源清理时的归属条件。

名称包含 `_secret`、`password`、`private_key`、`token` 或证书内容的变量禁止进入 OpenTofu 输入。

## Stack 所有权

### bootstrap

拥有：

- 必需 Project API；
- GitHub WIF pool、PR plan provider、Environment provider 与 attribute mapping；
- `plan`、`apply`、`deploy` Service Account 及最小 IAM；
- GitHub 身份模拟各 Service Account 的绑定。

它不拥有 state bucket、业务网络或运行资源。首次执行使用维护者本地 GCP 身份；完成后常规 plan/apply 通过 WIF。

### platform

拥有：

- 专用 VPC、子网、静态外部 IPv4和防火墙；
- Artifact Registry repository；
- proxy VM 与 runtime Service Account；
- `proxy-users`、`obfs-password` Secret Manager 容器与 Cloud Run runtime Service Account；
- Cloud Run subscription 服务的区域、ingress、权限、资源限制和 secret 引用。

部署工作流拥有 Cloud Run revision 的运行时字段（清单见[环境与交付](environments-and-delivery.md)的 Cloud Run 发布协议）：这些字段来自派生计算或 Secret Manager version，不作为 OpenTofu 变量存在，platform 的 Cloud Run resource 必须对全部这些字段声明 `lifecycle { ignore_changes }`，platform apply 不得覆盖它们。platform 仍然收敛 region、ingress、资源限制、Service Account 绑定和 secret 容器引用等结构性配置。

## 模块接口

每个 module 至少接收 `project_id`、`environment`、`resource_prefix` 和 `labels`，只返回消费者需要的稳定值。

platform 必须公开：

```text
proxy_ip_address
proxy_vm_name
proxy_vm_zone
artifact_repository_url
subscription_service_name
subscription_service_url
proxy_users_secret_id
obfs_password_secret_id
```

输出不得包含 private key、密码、token、证书正文、生成后的 sing-box 配置或 Secret Manager payload。

## 身份边界

| 身份 | 能力边界 |
| --- | --- |
| `github-plan` | 读取受管资源和 state；获取与释放 state lock；不能修改 GCP 资源 |
| `github-apply` | 修改 bootstrap、platform 两个 OpenTofu stack 声明的资源；不能读取 secret payload 或登录 VM |
| `github-deploy` | 读取 platform outputs、推送镜像、增加指定 secret version、更新 Cloud Run revision、通过 IAP/OS Login 发布 VM |
| `proxy-runtime` | 运行 VM；无 Project 级管理角色，无 Secret Manager 读取权限 |
| `subscription-runtime` | 仅读取指定环境的 `proxy-users` 与 `obfs-password` secret |

WIF attribute mapping 必须包含 `repository_id`、`repository_owner_id`、`event_name`、`ref` 和 `sub`。绑定使用不可变 repository ID。PR plan provider 只接受 `event_name=pull_request` 或 `ref=refs/heads/main`；Environment provider 的 `sub` 必须匹配 `repo:<owner>/<repo>:environment:<environment>`，只允许模拟 apply/deploy 身份。

**Needs test coverage:** production 身份不能读取或修改 development state，反之亦然，因为跨环境授权错误不会阻止单环境部署继续成功。

## 网络规则

VM ingress 固定为：

| 来源 | 协议/端口 | 目标 |
| --- | --- | --- |
| `0.0.0.0/0` | TCP 443 | proxy VM network tag |
| `0.0.0.0/0` | UDP 443 | proxy VM network tag |
| `35.235.240.0/20` | TCP 22 | proxy VM network tag |

不得创建其他公网 ingress。VM 启用 OS Login，不维护项目级 SSH key metadata。

## 生命周期规则

- Provider 和 module 版本必须固定；提交 `.terraform.lock.hcl`。
- production 不得与 development 共用 bucket、state prefix、Service Account、VPC、静态 IP、secret 或运行资源。
- `platform` 连续两次 apply 的第二次必须为零变更，才算环境收敛。
- destroy 只能作用于一个明确环境，且调用层必须要求输入该环境完整 Project ID。
- Project、Billing、state bucket 和 bootstrap WIF 不属于常规 platform destroy 范围。

## 关联

- Architecture：[overview.md](../architecture/overview.md)
- ADR：[ADR-0001](../adr/0001-manage-gcp-with-opentofu.md)、[ADR-0002](../adr/0002-separate-proxy-and-subscription-runtimes.md)
- Design：[环境与交付](environments-and-delivery.md)
