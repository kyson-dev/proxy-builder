# 代理与订阅契约

本文唯一拥有用户 JSON schema、代理 VM 文件与切换规则、密钥派生，以及订阅服务 HTTP 接口。

**实现状态：** 尚未实现

## 用户 Schema

`PROXY_USERS_JSON` 必须是 UTF-8 JSON 对象：

```json
{
  "version": 1,
  "users": [
    {
      "name": "alice",
      "enabled": true,
      "vless_uuid": "00000000-0000-4000-8000-000000000000",
      "hy2_password": "high-entropy password",
      "subscription_token": "high-entropy token"
    }
  ]
}
```

规则：

- 顶层只允许 `version` 与 `users`；`version` 当前只能为整数 `1`。
- 用户对象五个字段都必需，不允许未知字段。
- `name` 为 1–64 个可打印字符，在同一环境唯一。
- `vless_uuid` 必须是规范小写 UUID，在同一环境唯一。
- `hy2_password` 与 `subscription_token` 至少 24 个字符；token 在同一环境唯一。
- `enabled=false` 的用户不进入 sing-box 配置，订阅请求返回 `403`。
- JSON 中至少有一个 enabled 用户才能发布。

**Needs test coverage:** 重复 UUID、密码或 token 必须使整个发布失败，因为部分接受会让用户身份和订阅授权错配。

## 密钥与派生值

| 值 | 来源或算法 |
| --- | --- |
| Reality private key | `REALITY_PRIVATE_KEY` Secret |
| Reality public key | 使用目标 sing-box 版本从 private key 派生 |
| Reality short ID | `hex(SHA-256(private key))[0:16]`，即 8-byte lowercase hex |
| HY2 certificate/key | `HY2_CERT_PEM` 与 `HY2_KEY_PEM` Secrets |
| HY2 certificate fingerprint | 对证书 DER 字节计算 SHA-256，输出 uppercase colon-separated hex |
| HY2 SPKI fingerprint | 对 `RawSubjectPublicKeyInfo` 计算 SHA-256，输出标准 Base64 |
| 代理地址 | OpenTofu `proxy_ip_address` output |

发布前必须验证 private/public key 可派生、证书与私钥匹配、证书当前有效，并且 SAN 包含环境 `hy2_sni`。不在 VM 上生成或自动轮换 HY2 证书。

> Assumption, unverified: Hysteria2 URI、Clash Meta 与 sing-box 分别接受上述证书或 SPKI 指纹格式；如果客户端字段要求不同，订阅输出和测试向量必须在实现前同步调整。

## VM 运行布局

```text
/opt/proxy-builder/
├── releases/<git-sha>/
│   ├── release.json
│   ├── docker-compose.yml
│   └── config.json
├── current -> releases/<git-sha>
├── secrets/
│   ├── hysteria2.crt
│   └── hysteria2.key
└── staging/
```

`releases/` 只包含生成后的 sing-box 配置和非秘密发布元数据。`config.json` 含用户凭据，目录权限必须为 `0700`、文件为 `0600`，不得上传为 GitHub artifact。

`secrets/` 不属于 release，证书轮换独立于普通文件包；写入时机（何时判定需要重新写入证书和私钥）由[环境与交付](environments-and-delivery.md)的 VM 发布协议拥有。`staging/` 只能保存当前发布的临时输入，成功或失败后都必须清理。

Docker Compose 只包含一个 `sing-box` service：

- image 必须使用 digest，禁止 tag；
- 映射 `443:443/tcp` 与 `443:443/udp`；
- 只读挂载 `current/config.json` 和 `secrets/`；
- restart policy 为 `unless-stopped`；
- 不映射 TCP 22、8080 或其他应用端口。

## 配置切换算法

1. 在新 release 目录生成 `config.json`，不得修改 `current`。
2. 对 JSON schema 和用户唯一性执行校验。
3. 使用目标 image digest 执行 `sing-box check`。
4. 原子替换 `current` symlink，重建 sing-box container。
5. 验证 container healthy、TCP 443 与 UDP 443 探测通过。
6. 任一运行检查失败时恢复旧 symlink 并重建旧 container；旧版本健康才报告“回滚成功”。

最多保留当前、上一版和一个失败诊断 release。运行秘密不得写入命令行参数或日志。

**Needs test coverage:** 任何预检失败不得改变 `current`，因为旧代理继续运行会掩盖一次非原子的配置写入。

## 订阅服务配置

服务从普通环境变量读取：

```text
PROXY_IP
REALITY_PUBLIC_KEY
REALITY_SHORT_ID
REALITY_DEST
HY2_SNI
HY2_CERT_SHA256
HY2_SPKI_SHA256
```

`OBFS_PASSWORD` 与 `PROXY_USERS_JSON` 只能通过 Secret Manager volume 或 secret environment reference 注入。用户 JSON 启动时解析一次；解析失败或没有 enabled 用户时进程不得 ready。

服务不得访问 GCE API、VM 文件系统或公网 IP 探测服务。

## HTTP API

### 健康检查

```http
GET /healthz
```

- `200 application/json`：`{"status":"ok"}`，仅表示配置已加载且服务可响应。
- 其他 method 返回 `405`；其他健康路径返回 `404`。

### 获取订阅

```http
GET /v1/subscription?token=<token>&format=<format>
```

`format` 必填，只允许：

| 值 | `Content-Type` | 正文 |
| --- | --- | --- |
| `base64` | `text/plain; charset=utf-8` | VLESS 与 HY2 URI 按行连接后做标准 Base64 |
| `clash` | `text/yaml; charset=utf-8` | 可导入 Clash Meta 的 YAML |

不得根据 User-Agent、Accept 或客户端 IP 猜测格式。成功响应必须包含 `Cache-Control: no-store`。

错误固定为 JSON：

```json
{"error":{"code":"invalid_token","message":"subscription token is invalid"}}
```

| 情形 | HTTP | code |
| --- | ---: | --- |
| 缺少 token | 400 | `missing_token` |
| 缺少或不支持 format | 400 | `invalid_format` |
| token 不存在 | 401 | `invalid_token` |
| 用户被禁用 | 403 | `user_disabled` |
| 配置未就绪 | 503 | `service_unavailable` |
| 其他 path | 404 | `not_found` |
| 非 GET method | 405 | `method_not_allowed` |

比较 token 必须使用 constant-time comparison。日志可记录 request ID、状态码、format、延迟和不可逆用户标识；不得记录 query string、token、密码、UUID、完整代理 URI 或订阅正文。

**Needs test coverage:** 缺失、无效和 disabled token 的状态码与 code 保持稳定，因为客户端鉴权错误不能依赖日志才能区分。

**Needs test coverage:** 日志在所有 4xx/5xx 路径都不包含请求 token，因为失败请求仍会正常完成并可能绕过人工检查。

## 关联

- Architecture：[overview.md](../architecture/overview.md)
- ADR：[ADR-0002](../adr/0002-separate-proxy-and-subscription-runtimes.md)、[ADR-0003](../adr/0003-own-and-deliver-application-secrets.md)
- Design：[基础设施与身份](infrastructure-and-identity.md)、[环境与交付](environments-and-delivery.md)
