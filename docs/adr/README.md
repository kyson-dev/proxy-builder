# 架构决策记录

[Architecture](../architecture/overview.md) 描述系统现在是什么；本目录记录它为什么改变。

当决定改变架构原则、组件职责、状态所有权，或改变后必须同步更新其他文档时，新增 ADR。普通命名和目录调整不写 ADR。

状态只有：

```text
Accepted                  当前有效
Superseded by ADR-NNNN    已被后续决策取代
```

Accepted 后不得重写正文。改变决定时新增 ADR，并在两份记录中互相链接。

模板：[ `_template.md` ](_template.md)。

## 索引

| # | 决策 | 状态 | 日期 |
| --- | --- | --- | --- |
| 0001 | [使用 OpenTofu 管理 GCP，Bash 管理过程性操作](0001-manage-gcp-with-opentofu.md) | Accepted | 2026-08-23 |
| 0002 | [分离代理与订阅服务运行环境](0002-separate-proxy-and-subscription-runtimes.md) | Accepted | 2026-08-23 |
| 0003 | [划分应用秘密的维护与运行时投递](0003-own-and-deliver-application-secrets.md) | Accepted | 2026-08-23 |
