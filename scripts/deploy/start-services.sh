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
    if [[ -z "$SING_BOX_DATA_DIR" ]]; then
        die "SING_BOX_DATA_DIR 环境变量未设置"
    fi
    log_substep "数据目录: $SING_BOX_DATA_DIR"
    
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
