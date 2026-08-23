# 0001. 使用 OpenTofu 管理 GCP，Bash 管理过程性操作

**状态：** Accepted  
**日期：** 2026-08-23  
**影响：** GCP 基础设施、state、WIF/IAM、Shell 脚本、GitHub Actions

## 背景

当前 Bash 脚本直接查询并修改 WIF、IAM、VM、Artifact Registry 和防火墙。系统没有声明式 state，资源差异难以在变更前审查，也无法可靠证明重复执行后没有漂移。

同一组脚本还承担交互、资源创建、本地配置写入和部署准备，使 GCP 资源生命周期与过程性操作难以分开测试和授权。

## 决定

GCP 项目内的持久资源由 OpenTofu 声明和管理；Bash 只负责 state bucket 的最小 bootstrap、主机供给、应用发布、校验、健康检查和回滚等过程性操作。

每个环境使用独立 GCS bucket 和独立 state。基础身份栈与常规平台栈使用不同 state prefix。现有资源不导入；development 验证完成后再重建 production。

本轮不建立独立的应急/备用 VM stack；原因见 [ADR-0002](0002-separate-proxy-and-subscription-runtimes.md)。

WIF 使用不可变 GitHub repository ID 约束信任，并把 plan、apply、deploy 和 runtime 身份分开。

## 理由

OpenTofu 提供可审查的 plan、依赖图、state locking 和幂等收敛，适合拥有持续生命周期的云资源。Bash 适合表达有顺序、需要探测结果或需要原子回滚的主机与发布过程。

按环境和职责拆分 state 与身份，使 development 的错误不能直接修改 production，也使 PR plan 不需要部署权限。

## 未采用方案

| 方案 | 未采用原因 |
| --- | --- |
| 继续只用 Bash 管理 GCP | 无权威期望状态，变更预览、漂移检测和销毁边界不足 |
| 用 OpenTofu 管理主机内每个发布步骤 | 过程性发布、健康判断和原子回滚不适合资源图模型 |
| development 与 production 共用 state | 扩大锁、权限和误操作影响范围 |
| 导入全部现有资源 | 当前允许停机重建；导入会把旧命名和权限结构带入目标模型 |

## 后果

- 需要维护 OpenTofu 版本、provider lock file、模块接口和 state bucket。
- state bucket 必须先存在，因此仍保留一个范围严格的幂等 Bash bootstrap。
- GCP 控制面修改原则上必须进入 OpenTofu；紧急手工修改会在后续 plan 中表现为漂移。
- production 重建必须等待 development 的两次收敛验证和端到端验收。
- OpenTofu state、plan 和变量不得承载应用秘密。

## 关联

- Architecture：[overview.md](../architecture/overview.md)
- Design：[基础设施与身份](../design/infrastructure-and-identity.md)、[环境与交付](../design/environments-and-delivery.md)
- 后续决策：[ADR-0002](0002-separate-proxy-and-subscription-runtimes.md)、[ADR-0003](0003-own-and-deliver-application-secrets.md)
