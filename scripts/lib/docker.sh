#!/bin/bash
# ==============================================================================
# Docker 相关工具函数
# ==============================================================================

# 防止重复加载
if [[ -n "${_LIB_DOCKER_LOADED:-}" ]]; then
    return 0
fi
_LIB_DOCKER_LOADED=1

# ------------------------------------------------------------------------------
# 获取 Docker 命令（检测是否需要 sudo）
# ------------------------------------------------------------------------------
get_docker_cmd() {
    if docker info >/dev/null 2>&1; then
        echo "docker"
    elif sudo docker info >/dev/null 2>&1; then
        echo "sudo docker"
    else
        echo ""
        return 1
    fi
}
