#!/bin/bash
# ==============================================================================
# 启动 Docker Compose 服务 (Sing-box 原生版本)
# 注意: 此脚本应被主脚本 source，依赖库由主脚本加载
# ==============================================================================

# 如果直接运行，加载依赖
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_SELF_DIR}/../lib/common.sh"
    source "${_SELF_DIR}/../lib/docker.sh"
fi

# ------------------------------------------------------------------------------
# 主函数
# ------------------------------------------------------------------------------
start_services() {
    local compose_file="${1:-docker-compose.yml}"
    local docker_cmd
    docker_cmd=$(get_docker_cmd)
    
    if [[ -z "$docker_cmd" ]]; then
        die "无法运行 Docker"
    fi
    
    log_step "启动服务"
    
    # 验证环境变量
    if [[ -z "$DATA_ROOT" ]]; then
        die "DATA_ROOT 环境变量未设置"
    fi
    log_substep "数据目录: $DATA_ROOT"
    
    # 自动且精确配置本服务镜像所需的 GCP Artifact Registry 凭证助手
    # 逻辑：从 SUBSCRIPTION_IMAGE 中（如 us-central1-docker.pkg.dev/...）提取真实的仓库域名，利用 gcloud 幂等配置
    if [[ "${SUBSCRIPTION_IMAGE:-}" =~ ([a-z0-9-]+-docker\.pkg\.dev) ]]; then
        local registry="${BASH_REMATCH[1]}"
        log_substep "动态配置 Artifact Registry 凭证助手: $registry"
        if command -v gcloud &>/dev/null; then
            gcloud auth configure-docker "$registry" --quiet >/dev/null 2>&1 || true
            if [[ "$docker_cmd" == *"sudo"* ]]; then
                sudo gcloud auth configure-docker "$registry" --quiet >/dev/null 2>&1 || true
            fi
        fi
    fi

    # 拉取最新镜像
    log_substep "拉取最新镜像..."
    $docker_cmd compose -f "$compose_file" pull
    
    # 启动服务
    # --remove-orphans 清理不在 compose 文件中定义的旧容器。
    # --force-recreate 强制重建所有容器：sing-box 的 config.json、subscription 的
    # cert.pem 都是 bind mount 且只在启动时读一次（sing-box 读 config.json；
    # subscription 的 loadConfig()/loadCertFingerprints() 只在 main() 里跑一次），内容
    # 变化不会被 compose 视为服务定义变化。若某次部署只重新生成了 config.json 或轮换了
    # 证书，但镜像 tag/环境变量都没变，普通 up -d 不会重建这两个容器，导致它们继续用旧
    # 内容跑（config 不生效，或 subscription 发出跟服务端证书对不上的旧指纹）。
    # 注：users.json 不受影响，subscription 的 loadUsers() 是每次请求都重新读的。
    log_substep "启动 Sing-box..."
    $docker_cmd compose -f "$compose_file" up -d --remove-orphans --force-recreate

    log_success "服务已启动"
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    start_services "${1:-docker-compose.yml}"
fi
