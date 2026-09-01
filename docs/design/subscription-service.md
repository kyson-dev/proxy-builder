# 订阅服务

本文唯一拥有 subscription 进程配置、启动行为、HTTP API、订阅格式和日志规则。

**实现状态：** development Cloud Run 已部署，公开健康、token 隔离、订阅正文和双协议 E2E 已验证；production 尚未激活。

## 进程配置

普通环境变量：

```text
PROXY_IP
REALITY_PUBLIC_KEY
REALITY_SHORT_ID
REALITY_DEST
HY2_SNI
HY2_CERT_SHA256
HY2_SPKI_SHA256
PORT                    # 可选，默认 8080
```

Secret Manager reference 注入的环境变量：

```text
OBFS_PASSWORD
PROXY_USERS_JSON
```

进程不读取 VM 文件、GCE metadata 或公网 IP 探测服务。启动时一次性严格校验全部配置；失败时只记录字段级错误并退出非零，不启动 unready HTTP server。

校验至少覆盖：IPv4 地址、X25519 Reality public key、16 位 lowercase hex short ID、`host:port` Reality target、hostname SNI、uppercase colon-separated certificate SHA-256、标准 Base64 编码的 32-byte SPKI SHA-256、非空且至少 24-byte 的 obfs password，以及[共享用户 Schema](proxy-and-subscription-contracts.md)。

监听地址固定为 `:<PORT>`。容器以非 root UID/GID 运行，根文件系统不需要写权限，也不需要 CA bundle 或出站网络。

## HTTP API

Cloud Run 默认 HTTPS URL 公开且不执行 Invoker IAM 检查。Google 身份不属于客户端接口；除健康检查外，公开请求必须通过本节定义的应用 token 边界。

### 健康检查

```http
GET /v1/health
```

返回 `200 application/json`：

```json
{"status":"ok"}
```

仅 GET 有效；其他 method 返回固定 JSON `405 method_not_allowed`。

### 获取订阅

```http
GET /v1/subscription?token=<token>&format=<format>
```

`format` 必填且只允许：

| 值 | `Content-Type` | 正文 |
| --- | --- | --- |
| `base64` | `text/plain; charset=utf-8` | VLESS 与标准 HY2 URI 按行连接后做标准 Base64，无尾随换行 |
| `clash` | `text/yaml; charset=utf-8` | 可由 Mihomo 解析的确定性 YAML |

不得根据 User-Agent、Accept 或客户端 IP 猜测格式。该路径的全部成功与失败响应都包含 `Cache-Control: no-store`。

错误正文固定为：

```json
{"error":{"code":"invalid_token","message":"subscription token is invalid"}}
```

| 情形 | HTTP | code |
| --- | ---: | --- |
| 缺少 token | 400 | `missing_token` |
| 缺少或不支持 format | 400 | `invalid_format` |
| token 不存在 | 401 | `invalid_token` |
| 用户被禁用 | 403 | `user_disabled` |
| 其他 path | 404 | `not_found` |
| 非 GET method | 405 | `method_not_allowed` |

配置不可用由启动失败表达，不保留运行时 `503 service_unavailable` 状态。

## Token 匹配

启动时为每个 token 计算 SHA-256。请求查找必须遍历全部用户并对固定长度 digest 使用 constant-time comparison；不得用原文 token 作为 map key。

disabled 用户仍参与 token 匹配，以稳定返回 `403`。重复 token 在启动时已被 schema 拒绝，因此一次请求最多命中一个用户。

## 输出规则

VLESS URI 固定包含 TCP、`xtls-rprx-vision`、Reality、Chrome fingerprint、环境 SNI、公钥和 short ID。所有 userinfo、query 与 fragment 值必须按 URI 组件编码。

HY2 URI 使用 `hysteria2://` scheme，固定包含：

```text
sni=<HY2_SNI>
insecure=1
pinSHA256=<HY2_CERT_SHA256>
pubKeySHA256=<HY2_SPKI_SHA256>
obfs=salamander
obfs-password=<encoded password>
```

`pubKeySHA256` 是供 sing-box 1.13+ 客户端映射到 `tls.certificate_public_key_sha256` 的扩展字段；标准 Hysteria2 客户端继续使用 `insecure=1` 与 `pinSHA256`。不得添加其他自定义 query。Clash YAML 为每名用户生成 VLESS、Hysteria2 两个 proxy 和一个包含二者与 `DIRECT` 的 select group；所有用户值必须通过 YAML encoder 输出，不拼接未转义 scalar。

## 日志

每个请求生成服务端随机 request ID，并把它返回为 `X-Request-ID`。单条结构化日志只允许：request ID、path 类型、status、format、latency 和 `hex(SHA-256(subscription_token))[0:16]` 用户标识。

不得记录 raw query、token、name、password、UUID、private/public key、代理 URI、订阅正文或环境变量值。panic recovery 也只返回固定 `500 internal_error`，并遵守同一日志边界。

Cloud Run 自动 request log 的 `requestUrl` 会包含 query token，因此 platform 按精确 service name 排除 `run.googleapis.com/requests`。这不改变应用日志规则，也不得扩展为排除 stdout/stderr 应用日志。

## Cloud Run Revision

OpenTofu 拥有 `/v1/health` startup probe。部署工作流后续只拥有 image 与上述普通/secret 环境变量，并以 no-traffic revision 发布；流量迁移属于[环境与交付](environments-and-delivery.md)。公网验证不得使用会被 Cloud Run 前端截获的 `/healthz`。

## 关联

- Architecture：[overview.md](../architecture/overview.md)
- ADR：[ADR-0002](../adr/0002-separate-proxy-and-subscription-runtimes.md)、[ADR-0003](../adr/0003-own-and-deliver-application-secrets.md)、[ADR-0004](../adr/0004-public-cloud-run-with-application-auth.md)
- Design：[共享契约](proxy-and-subscription-contracts.md)、[环境与交付](environments-and-delivery.md)
