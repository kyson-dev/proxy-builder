#!/bin/bash
# ==============================================================================
# 全局工作路径定义 (Single Source of Truth)
# ==============================================================================
[[ -n "${_LIB_PATHS_LOADED:-}" ]] && return 0
_LIB_PATHS_LOADED=1

export APP_DIR="/opt/proxy/app"
export DATA_DIR="/opt/proxy/data"
export SING_BOX_DATA_DIR="${DATA_DIR}/sing-box"
