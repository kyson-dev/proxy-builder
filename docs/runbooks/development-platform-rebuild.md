# Development platform 重建

**使用时机：** 保留 bootstrap/WIF/state 与秘密备份，完整销毁并重建 development platform  
**风险等级：** 高  
**最后复核：** 2026-08-24

## 前置条件

- [ ] 已确认允许 development 中断；没有同环境 apply/deploy/destroy 在运行。
- [ ] `.secrets/development/` 五项文件存在且权限正确；GitHub audit 成功。
- [ ] 记录当前 commit 与 Project ID；`make validate` 成功。

此操作删除 platform stack 管理的 VM、IP、Cloud Run、Secret Manager 容器和镜像仓库。它不删除 bootstrap stack、GCS state bucket、WIF、GitHub 配置或本地 `.secrets`。

## 步骤

```bash
project_id="$(sed -nE 's/^project_id[[:space:]]*=[[:space:]]*"([^"]+)"/\1/p' infra/environments/development.tfvars)"
make destroy ENV=development STACK=platform CONFIRM_PROJECT_ID="$project_id"
make infra-apply ENV=development STACK=platform
make secrets-publish ENV=development
make deploy ENV=development GIT_REF="$(git rev-parse HEAD)"
make infra-plan ENV=development STACK=platform
```

对 deploy workflow 执行 `gh run watch <run-id> --exit-status`，确认双协议 E2E 后再恢复客户端使用。

## 成功标准

- bootstrap plan 未发生变更；platform 最终 plan 为零变更。
- VM、Cloud Run、request-log exclusion 与 Secret Manager 容器均已重建。
- 部署成功，新的 `make subscription-url` 输出可用。

## 失败处理

- destroy 失败：不要手工删资源；修复 OpenTofu 错误后重复 destroy。
- apply 失败：平台保持中断，修复后重复 apply；不要重建 bootstrap。
- deploy 返回 `21`：停止写操作并检查 VM/Cloud Run；首次重建发布没有 previous 可回滚是预期边界。

## 背景

- Design：[基础设施与身份](../design/infrastructure-and-identity.md)、[环境与交付](../design/environments-and-delivery.md)
