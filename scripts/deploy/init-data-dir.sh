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
    log_step "初始化数据目录"
    
    # 验证必要的变量（双重保险）
    if [[ -z "$SING_BOX_DATA_DIR" ]]; then
        die "数据目录环境变量未设置 (init_data_dir)"
    fi
    
    # 创建 Sing-box 数据目录结构
    ensure_dir "${SING_BOX_DATA_DIR}"
    ensure_dir "${SING_BOX_DATA_DIR}/cert"
    
    log_substep "数据根目录: $DATA_ROOT"
    log_substep "Sing-box 数据目录: $SING_BOX_DATA_DIR"
    log_substep "  - cert: ${SING_BOX_DATA_DIR}/cert"
    log_success "数据目录初始化完成"
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init_data_dir "$@"
fi
