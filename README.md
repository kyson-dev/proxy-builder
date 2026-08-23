# Proxy Builder

Proxy Builder 在 GCP 上运行基于 sing-box 的 VLESS Reality 与 Hysteria2 代理，并为授权用户提供订阅配置。

## 当前状态

仓库正在 `refactor/opentofu-platform` 分支进行破坏性重构。OpenTofu、共享 Go 契约、订阅服务、代理 VM release runtime 与 GitHub Actions 交付链已完成离线实现和验证，但尚未配置 GitHub、apply 或部署；当前在线环境仍由旧 Bash 资源和同一台 GCE VM 上的 sing-box/订阅容器提供服务。

当前系统组成见 [Architecture](docs/architecture/overview.md)。重构为什么发生见 [ADR 索引](docs/adr/README.md)，将要实现的具体契约见 [Design 索引](docs/design/README.md)。

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
| [CLAUDE.md](CLAUDE.md) | 修改仓库前的安全与阅读规则 |

## 范围外

本仓库不创建 GCP Project、不管理 Billing、域名或 DNS。production 与 development 使用独立 GCP Project；任何重建必须先在 development 验证。
