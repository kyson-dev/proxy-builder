# 0003. 划分应用秘密的维护与运行时投递

**状态：** Accepted  
**日期：** 2026-08-23  
**影响：** GitHub Environments、Secret Manager、OpenTofu、VM 发布、Cloud Run、用户 schema

## 背景

当前 GitHub Environment Secrets 同时保存 Project ID、区域、资源名、公钥和私钥。本地 `.env.<environment>` 保存同一批值，形成重复来源。部署工作流把秘密写进 `.env` 和 `users.json` 后与普通发布文件一起打包上传。

Cloud Run 需要可审计的运行时秘密投递，但把应用秘密交给 OpenTofu 会使明文进入 plan 或 state。

## 决定

版本库中的环境清单是非敏感期望状态的权威来源；GitHub Environment 是应用秘密的人工维护入口；Secret Manager 只保存需要交给 Cloud Run 的运行时副本。

GitHub Environment Secrets 固定为 `REALITY_PRIVATE_KEY`、`OBFS_PASSWORD`、`HY2_CERT_PEM`、`HY2_KEY_PEM` 和 `PROXY_USERS_JSON`。用户数据使用带 `version` 字段的对象 schema。

OpenTofu 只创建 Secret Manager secret 容器和 IAM，不创建 secret version。部署工作流为 Cloud Run 的用户数据与混淆密码写入新 version，并通过 IAP 的独立秘密通道把 VM 所需值送到目标主机；普通发布包不含秘密。

## 理由

该分工让非秘密配置可审查，让个人维护者继续从 GitHub Environment 管理密钥，并避免 OpenTofu state 成为秘密存储。Secret Manager 负责运行时访问控制、版本和审计，不成为第二个人工编辑入口。

固定 schema 和派生规则减少需要手工同步的值：Reality 公钥由私钥生成，证书指纹由固定证书计算。

## 未采用方案

| 方案 | 未采用原因 |
| --- | --- |
| 所有值都存 GitHub Secrets | 非秘密配置不可审查，且与本地副本持续漂移 |
| OpenTofu 创建 secret version | 敏感值会进入变量、plan 或 state |
| Secret Manager 成为人工维护源 | 增加第二套编辑流程，GitHub 发布无法明确拥有输入版本 |
| 继续把秘密放进发布压缩包 | 扩大 runner、临时文件和 VM 暂存区的暴露范围 |

## 后果

- 环境清单不得包含私钥、密码、token、证书私钥或完整用户对象。
- GitHub Variables/Secrets 和环境清单必须通过自动校验防止错放。
- Secret Manager 每次发布产生新 version，需要制定后续保留和轮换操作。
- VM 仍需要本地持久化运行秘密，但权限必须限制，且不得进入版本化普通 release 包。
- 日志和错误响应不得输出 token、密码、私钥或完整订阅内容。

## 关联

- Architecture：[overview.md](../architecture/overview.md)
- Design：[环境与交付](../design/environments-and-delivery.md)、[代理与订阅契约](../design/proxy-and-subscription-contracts.md)
- 前序决策：[ADR-0001](0001-manage-gcp-with-opentofu.md)、[ADR-0002](0002-separate-proxy-and-subscription-runtimes.md)
