# Development 首次激活

**使用时机：** 首次用 OpenTofu 与 WIF 创建并部署 development 新平台  
**风险等级：** 高  
**最后复核：** 2026-08-23  
**适用范围：** `development`，首次成功部署前

## 禁止事项

- 不设置 `PRODUCTION_OPERATIONS_ENABLED`，不选择 production。
- 不删除旧线上资源、本地迁移源、失败 revision 或 Secret Manager version。
- 任一步骤的预期结果不成立时停止，不继续后续步骤。

## 前置条件

- [ ] 当前分支已推送到 GitHub，工作区干净，`make validate` 成功。
- [ ] `gcloud` 当前账号可管理 development Project，ADC 可供 OpenTofu 使用；`gh auth status` 成功。
- [ ] OpenTofu 为 1.12.1；本机有 Go、Docker、jq、ShellCheck 与 Actionlint 1.7.12。
- [ ] 五项秘密分别位于权限 `0600` 的文件：v1 users、Reality private key、obfs password、HY2 certificate、HY2 private key。

## 步骤

1. **验证或迁移秘密输入**

   旧数组 users 只执行一次：

   ```bash
   go run ./cmd/proxyctl migrate-users --input users.development.json --output /secure/path/users.v1.json
   scripts/secrets/generate-hy2-certificate.sh --sni "$(jq -r .hy2_sni config/environments/development.json)" --cert /secure/path/hysteria2.crt --key /secure/path/hysteria2.key
   go run ./cmd/proxyctl inspect-environment --users /secure/path/users.v1.json --private-key-file /secure/path/reality-private-key --obfs-password-file /secure/path/obfs-password --cert /secure/path/hysteria2.crt --key /secure/path/hysteria2.key --sni "$(jq -r .hy2_sni config/environments/development.json)" --output /tmp/proxy-builder-development-public.json
   ```

   预期结果：三个命令退出 `0`；最后文件只含 Reality 公钥、short ID 和证书指纹。已有证书时跳过生成命令。

2. **创建 state bucket 并本地 apply bootstrap**

   ```bash
   make bootstrap ENV=development
   make infra-apply ENV=development STACK=bootstrap
   ```

   预期结果：state bucket 启用 versioning，bootstrap apply 成功。

3. **导出 bootstrap outputs 并配置 GitHub**

   ```bash
   project_id="$(sed -nE 's/^project_id[[:space:]]*=[[:space:]]*"([^"]+)"/\1/p' infra/environments/development.tfvars)"
   tofu -chdir=infra/stacks/bootstrap init -reconfigure -backend-config="bucket=${project_id}-proxy-builder-tfstate" -backend-config="prefix=bootstrap"
   tofu -chdir=infra/stacks/bootstrap output -json >/tmp/proxy-builder-development-bootstrap.json
   scripts/github/configure.sh --environment development --bootstrap-output /tmp/proxy-builder-development-bootstrap.json
   scripts/github/publish-secrets.sh --environment development --users /secure/path/users.v1.json --reality-private-key /secure/path/reality-private-key --obfs-password /secure/path/obfs-password --cert /secure/path/hysteria2.crt --key /secure/path/hysteria2.key --sni "$(jq -r .hy2_sni config/environments/development.json)"
   scripts/github/audit.sh --environment development
   ```

   预期结果：audit 报告 development 所需 Variables 和五项 Secrets 名称齐全；不显示值。

4. **通过 GitHub Environment apply platform**

   ```bash
   branch="$(git branch --show-current)"
   gh workflow run infra-apply.yml --ref "$branch" -f environment=development -f stack=platform
   gh run list --workflow infra-apply.yml --branch "$branch" --event workflow_dispatch --limit 1
   ```

   观察最新 run，使用 `gh run watch <run-id> --exit-status` 等待。预期结果：platform apply 成功且 plan 没有秘密值。

5. **首次部署并观察结果**

   ```bash
   make deploy ENV=development GIT_REF="$(git rev-parse HEAD)"
   gh run list --workflow deploy.yml --branch "$(git branch --show-current)" --event workflow_dispatch --limit 1
   ```

   对最新 run 执行 `gh run watch <run-id> --exit-status`。预期结果：VM 先健康，随后 Cloud Run 候选 revision 的 health、Base64、Clash 校验成功并获得 100% 流量。

## 成功标准

- `scripts/github/audit.sh --environment development` 成功，日志与 artifact 不含五项秘密原文。
- platform 连续第二次 plan 为零变更；Cloud Run request-log exclusion 存在。
- VM TCP/UDP 443 健康，Cloud Run `/healthz` 返回 `200`，真实用户的 Base64 与 Clash 订阅可导入客户端。
- 成功后删除本地 development 旧 `.env` 与旧 users 数组文件；保留五项新秘密的离线备份。

## 失败处理

| 现象 | 处理 |
| --- | --- |
| bootstrap/platform apply 失败 | 停止；检查对应 run/plan，不运行 destroy，不发布秘密值。 |
| VM 返回 `20` | 新 release 失败且旧 release 已恢复；停止并检查失败诊断。 |
| VM 返回 `21` | 环境没有健康 release；停止全部发布并人工检查 VM。 |
| Cloud Run 候选失败 | 保留 VM 成功版本、失败 revision 和 secret version；修复后重新 dispatch。 |
| 切流后健康失败 | 确认 workflow 已把流量恢复到旧 revision；未恢复时停止并人工回滚。 |

## 背景

- Architecture：[overview.md](../architecture/overview.md)
- Design：[环境与交付](../design/environments-and-delivery.md)、[基础设施与身份](../design/infrastructure-and-identity.md)
- ADR：[ADR-0001](../adr/0001-manage-gcp-with-opentofu.md)、[ADR-0003](../adr/0003-own-and-deliver-application-secrets.md)
