# Development 用户管理

**使用时机：** 新增、启停或立即轮换 development 用户  
**风险等级：** 中  
**最后复核：** 2026-08-24

## 前置条件

- [ ] `.secrets/development/` 是当前灾难恢复副本，权限为 `0700/0600`。
- [ ] 目标 commit 已推送；`gh auth status` 成功；当前没有同环境部署在运行。

## 步骤

1. 只执行一个本地变更：

   ```bash
   make user-add ENV=development USER=<name>
   # 或 user-enable、user-disable、user-rotate
   make user-protocol-disable ENV=development USER=<name> PROTOCOL=hysteria2
   ```

   `rotate` 会立即替换 UUID、HY2 password 和 subscription token，没有重叠窗口，并保留总开关与协议权限；不得禁用最后一个 enabled 用户，也不得关闭某用户最后一个协议。

2. 检查文件权限和变更对象后发布并部署：

   ```bash
   make secrets-publish ENV=development
   make deploy ENV=development GIT_REF="$(git rev-parse HEAD)"
   gh run list --workflow deploy.yml --event workflow_dispatch --limit 1
   gh run watch <run-id> --exit-status
   ```

3. 对 enabled 用户取得新 URL：

   ```bash
   make subscription-url ENV=development USER=<name> FORMAT=base64
   ```

## 成功标准

- 部署会验证每种仍有已启用获授权用户的协议与公网订阅；对所有用户关闭的协议会跳过 E2E。
- 新增/启用用户可用；禁用用户收到 `403`；轮换后旧三项凭据立即失效。
- 本地 `users.json` 与 GitHub Secret 是同一次发布的版本。

## 失败处理

- 本地命令失败：未发布，修正输入后重试；不要手工拼接 JSON。
- secrets 已发布但部署失败：运行环境仍由部署事务恢复；修复后重新 publish 与 deploy，避免不清楚版本来源。
- 返回 `21`：停止用户操作，按[首次激活](development-first-activation.md)的环境故障规则检查。

## 背景

- Design：[共享契约](../design/proxy-and-subscription-contracts.md)、[环境与交付](../design/environments-and-delivery.md)
