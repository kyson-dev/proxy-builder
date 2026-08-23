# 代理与订阅共享契约

本文唯一拥有 proxy VM 与 subscription 服务共享的用户 schema、Reality 派生和 HY2 证书校验规则。VM 文件与切换规则见[代理 VM 运行时](proxy-vm-runtime.md)，HTTP 接口见[订阅服务](subscription-service.md)。

**实现状态：** Go 共享契约与 `proxyctl` 已实现并离线验证，尚未部署。

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
- `name` 为 1–64 个 Unicode code point；每个字符必须可打印，且首尾不得为空白。
- `vless_uuid` 必须是规范小写 UUID。
- `hy2_password` 与 `subscription_token` 的 UTF-8 编码至少 24 bytes。
- name、UUID、HY2 password 与 subscription token 在同一环境内分别唯一，包括 disabled 用户。
- `enabled=false` 的用户不进入 sing-box 配置；匹配其 token 的订阅请求返回 `403`。
- 至少有一个 enabled 用户才能发布或启动 subscription 服务。
- 解码必须拒绝尾随第二个 JSON value，而不是只读取第一个对象。

共享 Go package 是 schema 校验的代码权威。VM 发布 CLI 与 subscription 服务必须调用同一 package，不各自实现第二套规则。

## Reality 派生

`REALITY_PRIVATE_KEY` 必须是无 padding 的 URL-safe Base64，解码后恰好为 32-byte X25519 private key。

派生固定为：

```text
reality_public_key = base64url-no-padding(X25519-public(raw-private-key))
reality_short_id   = lowercase-hex(SHA-256(raw-private-key)[0:8])
```

private key 的字符串表示不参与 short ID 计算。实现必须用固定向量与目标 sing-box 版本的 `generate reality-keypair` 结果交叉验证。

## HY2 证书

`HY2_CERT_PEM` 与 `HY2_KEY_PEM` 必须满足：

- PEM 分别包含可解析的 X.509 leaf certificate 与对应 private key；
- certificate public key 与 private key 匹配；
- 当前时间位于 certificate `NotBefore` 与 `NotAfter` 之间；
- SAN 包含环境清单的 `hy2_sni`；Common Name 不作为 SAN 的回退；
- 发布使用 leaf certificate DER 的 SHA-256，输出 uppercase colon-separated hex。

本轮不向订阅服务传递 SPKI fingerprint，也不在标准 Hysteria2 URI 添加自定义 query 参数。

## `proxyctl` 接口

仓库构建一个静态 Linux amd64 CLI，子命令固定为：

```text
proxyctl validate-users --input <path>
proxyctl validate-release --input <path>
proxyctl derive-reality --private-key-file <path> --output <path>
proxyctl inspect-certificate --cert <path> --key <path> --sni <host> --output <path>
proxyctl render-sing-box --template <path> --users <path> \
  --private-key-file <path> --obfs-password-file <path> \
  --release <release.json> --output <path>
```

`derive-reality` 输出：

```json
{"reality_public_key":"base64url","reality_short_id":"16-lowercase-hex"}
```

`inspect-certificate` 输出：

```json
{"hy2_cert_sha256":"UPPERCASE:COLON:HEX"}
```

JSON 输出只含公开派生值。CLI 错误只包含字段名或输入文件角色，不得包含 private key、password、token、UUID、证书正文或生成后的 sing-box 配置。

## 关联

- Architecture：[overview.md](../architecture/overview.md)
- ADR：[ADR-0002](../adr/0002-separate-proxy-and-subscription-runtimes.md)、[ADR-0003](../adr/0003-own-and-deliver-application-secrets.md)
- Design：[代理 VM 运行时](proxy-vm-runtime.md)、[订阅服务](subscription-service.md)、[环境与交付](environments-and-delivery.md)
