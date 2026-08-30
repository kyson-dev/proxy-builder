# VM OS 镜像升级

**使用时机：** 将某个环境的 proxy VM 升级到经过选择的新版 Debian 12 镜像  
**风险等级：** 高  
**最后复核：** 2026-08-29  
**适用范围：** `development` 或 `production`，两者必须分开执行

## 前置条件

- [ ] 目标必须是 `projects/debian-cloud/global/images/debian-12-bookworm-vYYYYMMDD` 格式的具体镜像，不得使用 family 或 `latest`。
- [ ] `.secrets/<environment>/` 灾难恢复副本完整且权限仍为目录 `0700`、文件 `0600`；GitHub Environment 五项 Secrets 已发布。
- [ ] 没有同环境 apply、deploy 或 destroy 正在运行；production 审批与 main-only 保护有效。
- [ ] 已接受单 VM 中断：apply 会替换 VM、自动删除旧启动盘，并清除主机上的 current/previous release 与运行秘密。静态 IP 保持不变。

## 步骤

1. **只修改一个环境的镜像版本**

   更新 `infra/environments/<environment>.tfvars` 的 `vm_source_image`，执行：

   ```bash
   make validate
   make infra-plan ENV=<environment> STACK=platform
   ```

   预期：plan 中 proxy VM 是因启动镜像变化而替换；静态 IP、网络、Secret Manager 容器和 Cloud Run 服务不得被替换或删除。若包含其他变更，停止并拆分变更。

2. **应用受审查的基础设施变更**

   通过 `infra-apply.yml` 为同一 environment 执行 `stack=platform`，等待成功。不要在失败后运行 destroy。

3. **重新部署不可变应用版本**

   ```bash
   make deploy ENV=<environment> GIT_REF=<approved-main-commit>
   gh run list --workflow deploy.yml --event workflow_dispatch --limit 1
   gh run watch <run-id> --exit-status
   ```

   新 VM 没有 previous release；首次部署若在后续 Cloud Run/E2E 阶段失败，可能返回 `21`，此时停止写操作并人工核对 VM 与 Cloud Run。

4. **验收环境**

   ```bash
   make infra-plan ENV=<environment> STACK=platform
   ```

   预期：plan 为零变更，VM TCP/UDP 443、Cloud Run `/v1/health`、两种订阅格式及 VLESS/Hysteria2 E2E 全部通过。

5. **按环境晋级**

   development 成功并稳定后，另开变更将 production 的 `vm_source_image` 更新为同一版本；重新执行完整 plan、审批、apply、deploy 和验收。不得以 development 的结果跳过 production plan 或审批。

## 失败处理

| 现象 | 处理 |
| --- | --- |
| plan 除 VM 替换外还有其他资源删除/替换 | 停止，不 apply；拆分或修正意外漂移。 |
| platform apply 失败 | 保留 state 与现状，检查失败点后重新 plan/apply；不运行 destroy。 |
| 新 VM 已创建但 deploy 未成功 | 使用本地灾难恢复副本确认 GitHub Secrets，修复后重新 deploy。 |
| deploy 返回 `20` | 按部署日志确认旧应用 release 已恢复；修复候选后重试。 |
| deploy 返回 `21` | 停止写操作，人工检查 VM current、Cloud Run 实际流量和公网探测结果。 |

## 成功标准

- 目标环境 VM 的启动盘来自批准的具体镜像，platform plan 为零变更。
- 静态公网 IP 未改变，应用部署记录对应批准的 Git SHA。
- TCP/UDP 443、公网 health、订阅校验与双协议真实出站全部成功。
- 另一环境没有在同一操作中被修改；production 只有在 development 验证后才晋级。

## 风险

本项目没有备用 VM 或独立持久化应用盘。镜像升级不是原地升级，会造成服务中断并删除 VM 内回滚窗口；恢复依赖版本库、GitHub Environment Secrets、本地 `.secrets` 灾难恢复副本和重新部署。
