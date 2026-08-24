# Production 首次激活

**使用时机：** 将新架构首次部署到空的 `kyson-proxy-prod`，旧 `kyson-proxy-builder` 保持运行。
**风险等级：** 高
**最后复核：** 2026-08-24

## 前置条件

- [ ] 实现 PR 已通过验证并合入 `main`；在 `main` 记录待部署 commit SHA。
- [ ] `kyson-proxy-prod` 为 active 且 billing 已启用；本地 GCP Owner、`gh auth status`、OpenTofu、Go、Docker、jq、ShellCheck 和 Actionlint 可用。
- [ ] 根目录 `.env.production` 与 `users.production.json` 是常规文件；其中 `KYSON` 是唯一待重命名用户。
- [ ] 已知这次导入保留 UUID、subscription token、Reality 与 obfs，但生成新 HY2 password/证书；客户端将在最后导入新的订阅 URL。

禁止删除或修改 `kyson-proxy-builder`、旧 VM 或旧 IP。首次 platform 使用新建 `proxy-ipv4`。

## 步骤

1. 本地创建并校验新 production bundle：

   ```bash
   make secrets-import-production
   make validate
   ```

   预期：`.secrets/production/` 新建五个 `0600` 文件；`KYSON` 变为 `USA`，其他用户、UUID 和 token 未变；终端不输出秘密。

2. 创建 state bucket，先以本地 Owner plan/apply bootstrap：

   ```bash
   make bootstrap ENV=production
   make infra-plan ENV=production STACK=bootstrap
   make infra-apply ENV=production STACK=bootstrap
   ```

   预期：bucket 为 `kyson-proxy-prod-proxy-builder-tfstate` 且开启 versioning；bootstrap 创建 production WIF 与三种 GitHub 身份。

3. 配置 GitHub、替换应用秘密并启用 production gate：

   ```bash
   make github-configure ENV=production
   make secrets-publish ENV=production
   make github-clean-production-legacy CONFIRM=kyson-dev/proxy-builder:production
   make github-audit ENV=production
   ./scripts/github/configure.sh --environment production --enable-production
   ```

   预期：Environment 只保留五项新架构应用 Secret；production 仅允许 `main`，且需要当前登录的 GitHub 身份审批。旧 VM 不读取 GitHub Environment Secret，不受本步骤影响。

4. 在 GitHub Actions 的 `main` 手动运行 `Infrastructure apply`，选择 `production/bootstrap`，完成 Environment 审批后确认零变更。再手动运行 `Infrastructure plan`，选择 `production/platform`，核对只会在 `kyson-proxy-prod` 创建 `proxy-*` 资源和新的 `proxy-ipv4`。

5. 审批并运行 `Infrastructure apply` 的 `production/platform`。随后手动运行 `Deploy application`，选择 `production` 和第 1 步记录的 `main` commit SHA。

6. 等待 deploy workflow 的 health、Base64/Clash 和 VLESS/Hysteria2 E2E 全部成功。执行：

   ```bash
   make infra-plan ENV=production STACK=platform
   make subscription-url ENV=production USER=USA FORMAT=base64
   ```

   预期：platform 为零变更；把终端输出的新 URL 导入客户端。该 URL 含 token，不得写入日志、工单或 shell history。

## 后续旧 IP 接管

仅在新 URL 已验证并安排维护窗口后执行。先从旧 VM 解绑 `ip4`，等待 regional address 可移动所需时间，再将其移动到 `kyson-proxy-prod`。提交 `existing_static_ip_name = "ip4"`，通过 PR 或手动 plan 审核后 apply platform；该 apply 将 VM 指向迁入地址，并释放临时 `proxy-ipv4`。移动后的地址由 GCP 外部流程管理，OpenTofu 只引用它。

## 失败处理

- bundle、bootstrap 或 platform 失败：停止，不要操作旧项目；修复后重试对应阶段。
- GitHub audit 失败：不要启用 production gate；先恢复 Variables/Secrets 的精确集合。
- deploy 返回 `20`：两侧已回滚，检查脱敏诊断后重试；返回 `21`：停止所有写操作并人工检查 VM 与 Cloud Run。
- 新订阅或 E2E 失败：不处理旧 IP，继续使用旧服务；确认新平台恢复后才重新发布。

## 成功标准

- `kyson-proxy-prod` 的 bootstrap/platform 均可由 GitHub WIF 收敛，platform 第二次 plan 为零变更。
- Cloud Run 公开 health、token 认证、两种订阅格式和两个真实代理协议均通过。
- `.secrets/production/` 保留为受限灾难恢复副本，旧项目仍未被修改。

## 背景

- Design：[环境与交付](../design/environments-and-delivery.md)、[基础设施与身份](../design/infrastructure-and-identity.md)
- ADR：[ADR-0001](../adr/0001-manage-gcp-with-opentofu.md)、[ADR-0003](../adr/0003-own-and-deliver-application-secrets.md)
