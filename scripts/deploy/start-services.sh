#!/bin/bash
# ==============================================================================
# 启动 Docker Compose 服务
# 注意: 此脚本应被主脚本 source，依赖库由主脚本加载
# ==============================================================================

# 如果直接运行，加载依赖
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_SELF_DIR}/../lib/common.sh"
fi

# ------------------------------------------------------------------------------
# 获取 Docker 命令
# ------------------------------------------------------------------------------
get_docker_cmd() {
    if docker info >/dev/null 2>&1; then
        echo "docker"
    elif sudo docker info >/dev/null 2>&1; then
        echo "sudo docker"
    else
        die "无法运行 Docker"
    fi
}

# ------------------------------------------------------------------------------
# 主函数
# ------------------------------------------------------------------------------
start_services() {
    local compose_file="${1:-docker-compose.yml}"
    local docker_cmd
    docker_cmd=$(get_docker_cmd)
    
    log_step "启动服务"
    
    # 清理旧的 .env 文件
    if [[ -f .env ]]; then
        log_substep "清理旧的 .env 文件..."
        rm -f .env
    fi
    
    # 拉取最新镜像
    log_substep "拉取最新镜像..."
    $docker_cmd compose -f "$compose_file" pull
    
    # 启动服务
    log_substep "启动 Sing-box..."
    $docker_cmd compose -f "$compose_file" up -d --remove-orphans
    
    log_success "服务已启动"
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    start_services "${1:-docker-compose.yml}"
fi
