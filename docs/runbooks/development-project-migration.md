# Development 项目迁移

**使用时机：** 把 development 从一个已激活的 GCP Project 迁到另一个 Project，并保留本地应用秘密
**风险等级：** 极高  
**最后复核：** 2026-08-24

## 前置条件

- [ ] source 与 target Project ID、目标 `resource_prefix` 已书面确认；不删除任何 GCP Project、Billing 或共享 API。
- [ ] 本地管理员对两个 Project 有 Owner 权限；`.secrets/development/` 五个文件存在且均为 `0600`。
- [ ] 所有 development workflow 已结束；`make github-audit ENV=development` 成功。
- [ ] source platform、bootstrap state bucket 的名称已从 source Project ID 推导，未凭记忆输入。

## 步骤

1. **销毁 source platform**

   在 source tfvars 仍指向旧 Project 时，从 `main` 触发 `destroy.yml`，输入 `environment=development` 和精确 source Project ID。等待 workflow 成功，再以 GCP 控制面确认 VM、Cloud Run、Artifact Registry、Secret Manager 容器和静态 IP 均不存在。

2. **以本地 Owner 清理 source bootstrap 与 state**

   本地 Owner 必须执行此步；GitHub apply 身份不能安全删除自身与 backend 权限。

   ```bash
   tofu -chdir=infra/stacks/bootstrap init -reconfigure -input=false \
     -backend-config="bucket=<source-project>-proxy-builder-tfstate" -backend-config="prefix=bootstrap"
   tofu -chdir=infra/stacks/bootstrap destroy -auto-approve -input=false \
     -var-file=../../environments/development.tfvars
   gcloud storage rm --recursive --all-versions "gs://<source-project>-proxy-builder-tfstate/**"
   gcloud storage buckets delete "gs://<source-project>-proxy-builder-tfstate" --quiet
   ```

   预期：WIF、GitHub Service Account、自定义 Role、它们的 IAM 绑定和 source state bucket 不存在；已启用 GCP APIs 保留。

3. **切换仓库配置并验证**

   将 development tfvars 的 `project_id` 与完整 `resource_prefix` 更新为 target 值；执行 `make validate`。在 target Project 创建 state bucket，再以本地 Owner apply bootstrap：

   ```bash
   make bootstrap ENV=development
   make infra-apply ENV=development STACK=bootstrap
   make github-configure ENV=development
   make github-audit ENV=development
   make secrets-publish ENV=development
   ```

   预期：GitHub 的 `DEV_` Variables 与 development Environment Variables 全部指向 target Project；秘密值不读取、不重建。

4. **重建并验收 target platform**

   从 GitHub 触发并等待 development 的 bootstrap WIF 验证、platform apply 和 deploy。最后运行 `make infra-plan ENV=development STACK=platform` 与 `make subscription-url ENV=development USER=<user>`；导入新的 URL，确认 Base64/Clash 订阅和 VLESS/Hysteria2 E2E 成功。

## 失败处理

| 现象 | 处理 |
| --- | --- |
| source platform destroy 失败 | 停止，修复 OpenTofu 错误；不得手工删除未记录资源。 |
| source bootstrap/state 清理失败 | 保持 source tfvars，不切换 GitHub Variables；用本地 Owner 修复后重试。 |
| target bootstrap 失败 | source 已释放时不要回写旧 GitHub 身份；修复 target 权限或 API 后重试。 |
| target deploy/E2E 失败 | platform 保留，检查 workflow 的脱敏诊断并重新部署；首次发布没有 VM previous release 是预期边界。 |

## 成功标准

- source 不存在本项目 platform、bootstrap identity 或 state bucket；source GCP APIs 与 Project 保留。
- target 的 GitHub audit 成功、platform 第二次 plan 为零变更、五项秘密原样保留。
- target Cloud Run `/v1/health`、两种订阅格式和双协议 E2E 全部成功；旧订阅 URL 停止使用。

## 关联

- Design：[基础设施与身份](../design/infrastructure-and-identity.md)、[环境与交付](../design/environments-and-delivery.md)
