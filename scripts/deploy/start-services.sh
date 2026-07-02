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
    # --remove-orphans 会自动清理不在 compose 文件中定义的旧容器
    log_substep "启动 Sing-box..."
    $docker_cmd compose -f "$compose_file" up -d --remove-orphans
    
    log_success "服务已启动"
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    start_services "${1:-docker-compose.yml}"
fi
