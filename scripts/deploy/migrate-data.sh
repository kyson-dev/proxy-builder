#!/bin/bash
# ==============================================================================
# 数据迁移模块
# 将旧版本的数据迁移到新的持久化目录
# ==============================================================================

# 如果直接运行，加载依赖
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_SELF_DIR}/../lib/common.sh"
fi

# ------------------------------------------------------------------------------
# 主函数: 迁移数据
# 从旧的 ./s-ui 目录迁移到 ~/data/s-ui
# ------------------------------------------------------------------------------
migrate_data() {
    local old_dir="${1:-./s-ui}"
    local new_dir="${2:-${HOME}/data/s-ui}"
    
    log_step "检查数据迁移"
    
    local migrated=false
    
    # 迁移数据库
    if [[ -d "${old_dir}/db" ]] && [[ -n "$(ls -A "${old_dir}/db" 2>/dev/null)" ]]; then
        if [[ ! -d "${new_dir}/db" ]] || [[ -z "$(ls -A "${new_dir}/db" 2>/dev/null)" ]]; then
            log_substep "迁移数据库: ${old_dir}/db -> ${new_dir}/db"
            ensure_dir "${new_dir}/db"
            cp -r "${old_dir}/db/"* "${new_dir}/db/" 2>/dev/null || true
            migrated=true
        fi
    fi
    
    # 迁移证书
    if [[ -d "${old_dir}/cert" ]] && [[ -n "$(ls -A "${old_dir}/cert" 2>/dev/null)" ]]; then
        if [[ ! -d "${new_dir}/cert" ]] || [[ -z "$(ls -A "${new_dir}/cert" 2>/dev/null)" ]]; then
            log_substep "迁移证书: ${old_dir}/cert -> ${new_dir}/cert"
            ensure_dir "${new_dir}/cert"
            cp -r "${old_dir}/cert/"* "${new_dir}/cert/" 2>/dev/null || true
            migrated=true
        fi
    fi
    
    if [[ "$migrated" == true ]]; then
        log_success "数据迁移完成"
    else
        log_substep "无需迁移（新目录已有数据或旧目录为空）"
    fi
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    migrate_data "$@"
fi
