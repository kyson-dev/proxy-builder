# Design

本目录拥有重构目标的具体接口、格式、路径和规则。实现完成前，文档标记为“目标契约”；代码与文档冲突时，先确认是否需要新 ADR，再修改契约或实现。

没有具体名称、格式或规则的内容属于 Architecture；人工操作步骤属于 Runbook。单份超过约 200 行时按主题拆分并登记。

模板：[ `_template.md` ](_template.md)。新增文档必须登记；未登记的文档视为不存在。

## 索引

| 文档 | 唯一拥有的主题 | 实现状态 |
| --- | --- | --- |
| [基础设施与身份](infrastructure-and-identity.md) | OpenTofu 目录、stack/state、模块边界、资源与 IAM/WIF 接口 | 代码已实现，尚未 apply |
| [环境与交付](environments-and-delivery.md) | 环境清单、GitHub 配置、工作流和发布协议 | 环境清单与本地发布组件已实现；工作流尚未实现 |
| [代理与订阅共享契约](proxy-and-subscription-contracts.md) | 用户 schema、Reality 派生与 HY2 证书校验 | 代码已实现，尚未部署 |
| [代理 VM 运行时](proxy-vm-runtime.md) | 主机就绪、release bundle、Compose、原子切换与回滚 | 代码已实现，尚未部署 |
| [订阅服务](subscription-service.md) | 进程配置、HTTP API、订阅格式与日志 | 代码已实现，尚未部署 |
