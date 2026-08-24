# 代理 VM 运行时

本文唯一拥有 VM 主机就绪标记、release bundle、staging 输入、sing-box Compose、原子切换、健康判断和回滚规则。

**实现状态：** startup、bundle、Compose、发布与回滚代码已实现并离线验证，尚未在 GCE 部署。

## 主机供给接口

OpenTofu 通过 instance metadata 的 `startup-script` 下发幂等 Bash，并以 `proxy-bootstrap-sha256` metadata 保存脚本摘要。脚本以 root 执行，安装 Docker Engine、Compose v2、jq、OpenSSL、`iproute2` 与 `util-linux`，启用 BBR，限制 journald，并创建运行目录。

成功后必须把 metadata 中的摘要原样写入：

```text
/var/lib/proxy-builder/bootstrap.sha256
```

startup script 内容更新只原地更新 metadata，不自动重启或替换 VM。每次应用发布必须先比较 metadata 与本地标记；不一致返回 `host_bootstrap_outdated`，且不得修改 current、证书或容器。

metadata、startup script 与标记不得包含应用秘密。

## 目录布局

```text
/opt/proxy-builder/
├── releases/<release-id>/
│   ├── release.json
│   ├── docker-compose.yml
│   ├── config.json
│   └── cert/
│       ├── hysteria2.crt
│       └── hysteria2.key
├── current -> releases/<release-id>
├── previous -> releases/<release-id>
├── staging/<release-id>/
└── failed/<release-id>/
    ├── release.json
    └── failure.json
```

根目录、release、cert 和 staging 目录均为 root-owned `0700`；`config.json`、certificate/key 与 staging 输入均为 `0600`。普通发布只通过 `sudo` 运行，不向 OS Login 用户授予 docker group 权限。

## Release bundle

runner 侧构建入口：

```text
scripts/release/build-vm-bundle.sh \
  --environment development|production \
  --git-sha <40-lowercase-hex> \
  --run-id <github-run-id> \
  --run-attempt <positive-integer> \
  --created-at <RFC3339-UTC> \
  --output <archive-path>
```

archive 只包含：

```text
release.json
docker-compose.yml
sing-box.template.json
bin/proxyctl
bin/deploy-release
```

`release.json` 固定字段：

```json
{
  "schema_version": 1,
  "release_id": "<git-sha>-<run-id>-<run-attempt>",
  "environment": "development",
  "git_sha": "40-character lowercase commit SHA",
  "deployment_id": "<run-id>-<run-attempt>",
  "sing_box_image": "registry/repository@sha256:<digest>",
  "reality_dest": "host:port",
  "hy2_sni": "hostname",
  "created_at": "RFC3339 UTC"
}
```

bundle 从版本库环境清单生成，是该次发布的不可变快照。禁止 tag、绝对路径、符号链接、秘密文件和未登记成员。

## Staging 输入

秘密通过普通 bundle 之外的独立通道写入：

```text
inputs/reality-private-key
inputs/obfs-password
inputs/proxy-users.json
inputs/hysteria2.crt       # 可选
inputs/hysteria2.key       # 可选
```

前三项每次发布必需。首次发布必须同时提供 certificate/key；后续两者都缺失时复制 current release 的证书对，只提供一个时失败。每个 release 因此都是可独立恢复的完整快照。staging 在成功或失败后都必须删除。

## Compose 与配置

Compose 只运行一个 `sing-box` service：

- image 来自 `release.json.sing_box_image` 且必须为 digest；
- 映射 `443:443/tcp` 与 `443:443/udp`；
- 只读挂载 `current/config.json` 和 `current/cert/`；
- restart policy 为 `unless-stopped`；
- 不使用 host network，不映射其他端口，不包含 subscription service。

`proxyctl render-sing-box` 只把 enabled 用户写入 VLESS/HY2 inbound，并注入共享契约定义的 private key、short ID、Reality target、HY2 SNI 和 obfs password。

## 原子发布

host 入口固定为：

```text
sudo bin/deploy-release --bundle <directory> --inputs <directory>
```

发布持有非阻塞 `flock`，顺序固定为：

1. 校验 root 身份、主机摘要、目录权限、manifest、bundle allowlist 和全部输入。
2. 拉取 digest image，在临时 release 中生成配置并执行目标 image 的 `sing-box check`；current 保持运行。
3. 把新证书或 current 证书副本写入临时 release，并验证完整证书对。
4. 将临时 release 原子改名为不可变 final directory，再原子替换 `current` symlink。
5. 以固定 Compose project 重建 sing-box，轮询容器 Running，并确认宿主机 TCP/UDP 443 均监听。
6. 成功后把旧 current 写入 `previous`；只保留 current 与 previous。

激活失败时恢复旧 current 并重建旧容器，证书随 symlink 一并恢复。Cloud Run 后续失败时，runner 使用以下接口显式回滚已经健康提交的 VM release；`expected-current` 必须精确匹配，防止并发或误回滚：

```text
sudo bin/deploy-release --rollback --expected-current <release-id>
```

显式回滚把 `previous` 切为 current、健康检查后移除失败候选，并留下脱敏诊断。首次部署失败时移除 current、停止失败容器并返回 `21`，因为环境没有可恢复的健康 release。退出码固定为：

| code | 语义 |
| ---: | --- |
| `0` | 新 release 健康 |
| `10` | 预检失败，current 未改变 |
| `20` | 激活失败，旧 release 已恢复健康 |
| `21` | 激活失败且旧 release 未恢复健康 |

失败目录只保留 `release.json` 与脱敏的 `failure.json`，后者包含失败阶段、code 和时间；最多保留一份。不得保留 `config.json`、Docker 原始日志或 staging 输入。

## 关联

- Architecture：[overview.md](../architecture/overview.md)
- ADR：[ADR-0001](../adr/0001-manage-gcp-with-opentofu.md)、[ADR-0002](../adr/0002-separate-proxy-and-subscription-runtimes.md)
- Design：[共享契约](proxy-and-subscription-contracts.md)、[环境与交付](environments-and-delivery.md)
