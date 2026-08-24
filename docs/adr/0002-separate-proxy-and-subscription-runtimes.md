# 0002. 分离代理与订阅服务运行环境

**状态：** Accepted  
**日期：** 2026-08-23  
**影响：** GCE、Docker Compose、Cloud Run、网络、订阅 API、发布与故障边界

## 背景

当前 sing-box 与订阅服务运行在同一台 VM。订阅容器通过挂载读取代理用户文件和证书，并把 HTTP 8080 暴露到公网。应用发布、证书处理和 VM 故障会同时影响代理与订阅。

代理需要固定公网 IPv4、TCP/UDP 443、内核网络配置和直接的数据平面控制；订阅服务是短请求、无状态 HTTP API，不需要这些主机能力。

## 决定

每个环境保留一台可销毁重建的 GCE VM，只通过 Docker Compose 运行固定 digest 的 sing-box。订阅服务从 VM 移除，作为独立 Cloud Run 服务运行。

代理 VM 使用环境专属静态 IPv4，只公开 TCP/UDP 443；TCP 22 仅接受 IAP 地址段并使用 OS Login。Cloud Run 通过 HTTPS 提供订阅 API，不依赖读取 VM 文件或运行时探测 VM 地址。

本轮不提供应急/备用 VM 能力。现有 `.github/workflows/deploy-backup-vm.yml` 随旧工作流一并删除，不做替代；不由应用部署工作流临时创建未纳管资源。

## 理由

该边界让代理数据平面保留 VM 所需能力，同时让 HTTP 服务获得独立发布、扩缩容和运行身份。显式传递静态 IP、证书指纹和非秘密参数后，订阅服务可以保持无状态。

单 VM 符合个人项目的成本与可维护性目标；可重建和版本化 release 提供恢复能力，不把高可用复杂度引入当前范围。

## 未采用方案

| 方案 | 未采用原因 |
| --- | --- |
| 继续在 VM 上运行两个容器 | 生命周期、权限、文件和公网端口继续耦合 |
| 把全部服务迁移到 Cloud Run | 代理需要 TCP/UDP 443、固定地址和主机网络能力 |
| 建立多实例代理集群 | 当前可接受单实例中断，成本与状态协调不值得 |
| 部署时临时创建应急 VM | 资源不进入独立 state，难以审查、回收和限制权限 |
| 本轮建立独立 emergency stack | 应急 VM 与订阅端点（`PROXY_IP` 等 Cloud Run 字段是否随故障切换更新）的关系尚未定义；在此之前引入独立 stack 会带来未经论证的能力，留待 development 主线验证后按真实需求另立 ADR |

## 后果

- 每个环境需要 Cloud Run、Secret Manager 和独立 runtime Service Account。
- 订阅服务不能读取 VM 文件；所有运行输入必须来自显式配置和 Secret Manager。
- VM 发布必须支持配置预检、原子切换、健康检查和回滚。
- 静态 IPv4 会产生持续成本，VM 重建不得改变客户端端点。
- Cloud Run 与代理可能独立成功或失败，部署流程必须分别验证。

## 关联

- Architecture：[overview.md](../architecture/overview.md)
- Design：[基础设施与身份](../design/infrastructure-and-identity.md)、[代理与订阅契约](../design/proxy-and-subscription-contracts.md)
- 前序决策：[ADR-0001](0001-manage-gcp-with-opentofu.md)
