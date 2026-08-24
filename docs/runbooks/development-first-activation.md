# Development 首次激活

**使用时机：** 从空 development 环境创建并部署完整平台
**风险等级：** 高  
**最后复核：** 2026-08-24
**适用范围：** `development`，首次成功部署前

## 前置条件

- [ ] 重构 PR 已通过验证并合入 `main`；记录待部署的 main commit SHA，工作区干净。
- [ ] `gcloud` 活动账号可管理 development Project，ADC 可供 OpenTofu 使用；`gh auth status` 成功。
- [ ] OpenTofu 1.12.1、Go、Docker、jq、ShellCheck 和 Actionlint 1.7.12 可用。
- [ ] `infra/environments/development.tfvars` 与 `config/environments/development.json` 已复核。

禁止选择 production、设置 `PRODUCTION_OPERATIONS_ENABLED`，或删除 bootstrap/state bucket。任一步结果不符立即停止。

## 步骤

1. **本地创建全新秘密并验证仓库**

   ```bash
   make secrets-init ENV=development USER=<first-user>
   make validate
   ```

   预期：`.secrets/development/` 新建五个 `0600` 文件；命令不输出秘密且不访问 GitHub/GCP。目录已存在时必须失败，禁止覆盖。

2. **删除旧 development Environment**

   ```bash
   make github-reset ENV=development CONFIRM=kyson-dev/proxy-builder:development
   ```

   预期：只删除 development Environment 与两项受管 `DEV_` Repository Variables；production 完全不变。

3. **创建 state bucket 并 apply bootstrap**

   ```bash
   make bootstrap ENV=development
   make infra-apply ENV=development STACK=bootstrap
   ```

   预期：state bucket 启用 versioning；bootstrap 创建 WIF 和 plan/apply/deploy 身份。

4. **配置 GitHub 并发布秘密**

   ```bash
   make github-configure ENV=development
   make secrets-publish ENV=development
   make github-audit ENV=development
   ```

   预期：configure 只发布 bootstrap 的非秘密身份标识；publish 只写五项 Environment Secrets；audit 不显示值。

5. **先验证 GitHub bootstrap WIF，再 apply platform**

   ```bash
   branch="$(git branch --show-current)"
   gh workflow run infra-apply.yml --ref "$branch" -f environment=development -f stack=bootstrap
   gh run list --workflow infra-apply.yml --branch "$branch" --event workflow_dispatch --limit 1
   gh run watch <run-id> --exit-status
   gh workflow run infra-apply.yml --ref "$branch" -f environment=development -f stack=platform
   gh run list --workflow infra-apply.yml --branch "$branch" --event workflow_dispatch --limit 1
   gh run watch <run-id> --exit-status
   ```

   预期：platform apply 成功，plan 不含秘密；Cloud Run v2 状态为 `invokerIamDisabled=true`、`defaultUriDisabled=false`，service IAM 不含 `allUsers roles/run.invoker`。

6. **部署指定不可变 commit**

   ```bash
   make deploy ENV=development GIT_REF="$(git rev-parse HEAD)"
   gh run list --workflow deploy.yml --event workflow_dispatch --limit 1
   gh run watch <run-id> --exit-status
   ```

   预期：VM 健康；无流量 Cloud Run revision 通过 startup probe；按 revision name 切流后，公网 health 无需 Google 身份，缺少/伪造 token 分别返回 `400`/`401`，两种有效订阅格式与 VLESS、Hysteria2 真实出站 E2E 全部成功。

7. **验收并取得订阅 URL**

   ```bash
   make infra-plan ENV=development STACK=platform
   make subscription-url ENV=development USER=<first-user> FORMAT=base64
   ```

   预期：plan 为零变更；URL 可导入客户端。终端输出含 token，不要写入 shell trace、工单或日志。

## 失败处理

| 现象 | 处理 |
| --- | --- |
| bootstrap/platform 失败 | 停止，检查 plan/run；不运行 destroy。 |
| VM 返回 `20` | 旧 VM 已恢复；检查脱敏失败诊断后重新部署。 |
| 返回 `21` | 没有完整旧版本或回滚失败；停止写操作并人工检查两侧实际流量。 |
| Cloud Run 无流量 revision 创建或 startup probe 失败 | 应未切流并尝试回滚 VM；首次部署没有 previous，因而可能返回 `21`。 |
| 切流后 health、订阅或 E2E 失败 | 确认日志顺序为 Cloud Run 恢复旧 revision、VM 回滚；任一步未完成均按环境故障处理。 |

## 成功标准

- GitHub audit 成功且名称/Variable 值精确，日志/artifact 无秘密原文；platform 第二次 plan 为零变更。
- VM TCP/UDP 443、Cloud Run `/healthz` 与双协议真实出站均通过。
- `.secrets/development/` 继续以 `0700/0600` 保留为灾难恢复副本。

## 背景

- Design：[环境与交付](../design/environments-and-delivery.md)、[基础设施与身份](../design/infrastructure-and-identity.md)
- ADR：[ADR-0001](../adr/0001-manage-gcp-with-opentofu.md)、[ADR-0003](../adr/0003-own-and-deliver-application-secrets.md)
