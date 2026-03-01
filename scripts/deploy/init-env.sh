#!/bin/bash
# ==============================================================================
# 初始化并完善环境变量
# 
# 功能:
# 1. 设置路径相关的默认环境变量
# 2. 将所有必要的变量写入 .env 文件 (供 Docker Compose 使用)
# ==============================================================================

init_env() {
    local env_file="${1:-.env}"
    
    log_step "初始化环境配置"
    
    export DATA_ROOT="${DATA_ROOT:-${HOME}/data}"
    export SING_BOX_DATA_DIR="${SING_BOX_DATA_DIR:-${DATA_ROOT}/sing-box}"
    
    log_substep "配置路径:"
    log_substep "  DATA_ROOT: $DATA_ROOT"
    log_substep "  SING_BOX_DATA_DIR: $SING_BOX_DATA_DIR"

    # 2. 确保 .env 文件存在
    touch "$env_file"

    # 3. 更新/追加变量到 .env 文件
    # 使用临时文件处理，避免 grep/sed 的复杂性，确保最终文件包含正确的值
    
    # 3. 追加默认变量到 .env 文件 (非破坏性)
    log_substep "检查并补全配置到 $env_file ..."
    
    # 辅助函数: 如果变量不存在则追加
    append_if_missing() {
        local key="$1"
        local value="$2"
        
        if ! grep -q "^${key}=" "$env_file"; then
            echo "${key}=${value}" >> "$env_file"
            # log_substep "  + 追加: $key"
        fi
    }
    append_if_missing "DATA_ROOT" "$DATA_ROOT"
    append_if_missing "SING_BOX_DATA_DIR" "$SING_BOX_DATA_DIR"
    
    # 确保文件结尾有换行符（可选，为了美观）
    if [ -n "$(tail -c1 "$env_file")" ]; then
        echo "" >> "$env_file"
    fi
    
    log_success "环境配置初始化完成"
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 需要先加载 common.sh 中的 log 函数
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh" 2>/dev/null || true
    init_env
fi
