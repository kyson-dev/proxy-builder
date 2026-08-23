# Proxy Builder

Proxy Builder 在 GCP 上运行基于 sing-box 的 VLESS Reality 与 Hysteria2 代理，并为授权用户提供订阅配置。

## 当前状态

仓库正在 `refactor/opentofu-platform` 分支进行破坏性重构。OpenTofu 基础设施代码已完成离线验证但尚未 apply；当前运行环境仍由旧 Bash 资源和同一台 GCE VM 上的 sing-box/订阅容器提供服务。

当前系统组成见 [Architecture](docs/architecture/overview.md)。重构为什么发生见 [ADR 索引](docs/adr/README.md)，将要实现的具体契约见 [Design 索引](docs/design/README.md)。

## 当前开发检查

```bash
find scripts -type f -name '*.sh' -exec bash -n {} +
(cd services/subscription && go test ./...)
DATA_ROOT=/tmp/proxy-builder SUBSCRIPTION_IMAGE=subscription:test \
  REALITY_PUBLIC_KEY=test REALITY_SHORT_ID=00000000 \
  REALITY_DEST=example.com:443 docker compose config --quiet
```

现有基础设施和部署入口仍可从 `make help` 查看；它们会在新架构实现并验证后被替换。

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
