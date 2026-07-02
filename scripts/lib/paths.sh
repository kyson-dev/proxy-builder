#!/bin/bash
# ==============================================================================
# 全局工作路径定义 (Single Source of Truth)
# ==============================================================================
[[ -n "${_LIB_PATHS_LOADED:-}" ]] && return 0
_LIB_PATHS_LOADED=1

export PROXY_ROOT="/opt/proxy"
export APP_DIR="${PROXY_ROOT}/app"
export DATA_DIR="${PROXY_ROOT}/data"
