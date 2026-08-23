# CLAUDE.md

本文件是修改本仓库前必须阅读的工作规则。

## 项目边界

Proxy Builder 在 GCP 上提供基于 sing-box 的 VLESS Reality 与 Hysteria2 代理，并提供经过令牌鉴权的订阅 API。

仓库管理应用、GCP 项目内资源和交付流程；不创建 GCP Project、不绑定 Billing，也不管理域名或 DNS。

## 默认安全姿态

- production 与 development 必须保持独立的身份、state、网络、运行资源和秘密。
- 不得让应用秘密进入 Git、OpenTofu state/plan、容器镜像或普通发布包。
- 删除、重建或可能导致中断的 GCP 操作，必须先明确环境与 Project ID；不得删除 Project 或 Billing 配置。
- 目标设计尚未全部实现。Design 是重构契约，Architecture 只描述当前可运行实现；不得混淆两者。

## 修改前阅读

| 修改内容 | 先阅读 |
| --- | --- |
| 文档 | [docs/README.md](docs/README.md) |
| 组件职责或状态所有权 | [Architecture](docs/architecture/overview.md) 与 [ADR 索引](docs/adr/README.md) |
| 基础设施、交付或应用接口 | [Design 索引](docs/design/README.md) |
| 改变 Accepted 决策 | 新增 ADR，并将旧 ADR 标记为被取代；不要重写旧 ADR 正文 |

文档坚持一个事实只有一个权威位置。详细边界、篇幅限制和新增规则由 [docs/README.md](docs/README.md) 单独维护。
