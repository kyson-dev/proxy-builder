# Proxy Builder

Proxy Builder 在 GCP 上运行基于 sing-box 的 VLESS Reality 与 Hysteria2 代理，并为授权用户提供订阅配置。

## 当前状态

新架构已在 `development` 完成真实激活：OpenTofu 管理 GCP 资源与 WIF，GitHub Actions 通过分离的 plan/apply/deploy 身份发布，sing-box 运行在 GCE VM，订阅服务运行在公开入口的 Cloud Run，并由应用 token 认证用户。完整事务部署和 VLESS Reality/Hysteria2 出站 E2E 已通过；`production` 尚未激活。

当前系统组成见 [Architecture](docs/architecture/overview.md)。关键决策见 [ADR 索引](docs/adr/README.md)，具体契约见 [Design 索引](docs/design/README.md)。

## 当前开发检查

```bash
make validate
```

稳定的验证、OpenTofu 和 workflow dispatch 入口可从 `make help` 查看；production 操作在显式完成 GitHub 审批配置与审计前保持禁用。

## 文档

| 文档 | 内容 |
| --- | --- |
| [文档规则](docs/README.md) | 信息归属、边界和篇幅限制 |
| [当前架构](docs/architecture/overview.md) | 已实现组件、数据流和状态所有权 |
| [ADR](docs/adr/README.md) | 已接受的架构决策及原因 |
| [Design](docs/design/README.md) | OpenTofu、交付和应用目标契约 |
| [Runbooks](docs/runbooks/README.md) | 首次激活和后续人工操作步骤 |
| [CLAUDE.md](CLAUDE.md) | 修改仓库前的安全与阅读规则 |

## 范围外

本仓库不创建 GCP Project、不管理 Billing、域名或 DNS。production 与 development 使用独立 GCP Project；任何重建必须先在 development 验证。
