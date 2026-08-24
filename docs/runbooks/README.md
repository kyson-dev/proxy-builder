# Runbooks

按操作需求查找，而不是按实现文件名查找。

| 需求 | 文档 |
| --- | --- |
| 首次创建并激活 development 新平台 | [development 首次激活](development-first-activation.md) |
| 首次创建并激活独立 production 平台 | [production 首次激活](production-first-activation.md) |
| 迁移 development 到新的 GCP Project 并复用秘密 | [development 项目迁移](development-project-migration.md) |
| 新增、启停或轮换 development 用户 | [development 用户管理](development-user-management.md) |
| 保留 bootstrap 与秘密，重建 development platform | [development platform 重建](development-platform-rebuild.md) |

## 编写规则

模板：[ `_template.md` ](_template.md)。每份 Runbook 必须包含使用时机、前置条件、步骤、成功标准、失败处理、风险和最后复核日期；核心步骤应能在不阅读 Design 的情况下独立执行。
