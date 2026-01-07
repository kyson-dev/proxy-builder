#!/bin/bash
# ==============================================================================
# 初始化持久化数据目录
# 注意: 此脚本应被主脚本 source，依赖库由主脚本加载
# ==============================================================================

# 如果直接运行，加载依赖
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_SELF_DIR}/../lib/common.sh"
fi

# ------------------------------------------------------------------------------
# 主函数: 初始化数据目录
# 使用 DATA_ROOT 环境变量作为基础目录
# ------------------------------------------------------------------------------
init_data_dir() {
    local data_root="${DATA_ROOT:-${HOME}/data}"
    
    log_step "初始化数据目录"
    
    # 定义各服务的数据目录
    export S_UI_DATA_DIR="${data_root}/s-ui"
    export CADDY_DATA_DIR="${data_root}/caddy"
    
    # 创建 S-UI 数据目录结构
    ensure_dir "${S_UI_DATA_DIR}/db"
    ensure_dir "${S_UI_DATA_DIR}/cert"
    
    # 创建 Caddy 数据目录结构
    ensure_dir "${CADDY_DATA_DIR}/data"
    ensure_dir "${CADDY_DATA_DIR}/config"
    
    log_substep "数据根目录: $data_root"
    log_substep "S-UI 数据目录: $S_UI_DATA_DIR"
    log_substep "  - db: ${S_UI_DATA_DIR}/db"
    log_substep "  - cert: ${S_UI_DATA_DIR}/cert"
    log_substep "Caddy 数据目录: $CADDY_DATA_DIR"
    log_substep "  - data: ${CADDY_DATA_DIR}/data"
    log_substep "  - config: ${CADDY_DATA_DIR}/config"
    
    # 将数据目录变量写入 .env 文件，供 docker compose 使用
    log_substep "更新 .env 文件..."
    cat >> .env << 'ENV_EOF'

# 数据目录配置（由 deploy.sh 自动生成）
ENV_EOF
    echo "DATA_ROOT=${data_root}" >> .env
    echo "S_UI_DATA_DIR=${S_UI_DATA_DIR}" >> .env
    echo "CADDY_DATA_DIR=${CADDY_DATA_DIR}" >> .env
    
    log_success "数据目录初始化完成"
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init_data_dir "$@"
fi
