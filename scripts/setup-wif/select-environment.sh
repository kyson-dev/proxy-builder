#!/bin/bash
# ==============================================================================
# 选择环境 (production/development)
# 注意: 此脚本应被主脚本 source，依赖库由主脚本加载
# ==============================================================================

# 如果直接运行，加载依赖
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_SELF_DIR}/../lib/common.sh"
    source "${_SELF_DIR}/../lib/prompt.sh"
fi

# ------------------------------------------------------------------------------
# 主函数
# ------------------------------------------------------------------------------
select_environment() {
    log_step "Step 0: 选择环境"
    echo ""
    
    # 根据当前 git 分支推荐默认环境
    local current_branch=""
    local default_env=""
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    
    case "$current_branch" in
        main|master) default_env="production" ;;
        dev|develop|development) default_env="development" ;;
        *) default_env="" ;;
    esac
    
    if [[ -n "$default_env" ]]; then
        log_substep "检测到分支: $current_branch → 推荐环境: $default_env"
    fi
    
    echo ""
    echo "请选择部署环境:"
    echo "  1. production (main 分支 → 生产 VM)"
    echo "  2. development (dev 分支 → 测试 VM)"
    echo "  0. 退出"
    echo ""
    
    local selection
    while true; do
        if [[ "$default_env" == "production" ]]; then
            read -p "选择 (0-2) [默认: 1]: " selection
            selection="${selection:-1}"
        elif [[ "$default_env" == "development" ]]; then
            read -p "选择 (0-2) [默认: 2]: " selection
            selection="${selection:-2}"
        else
            read -p "选择 (0-2): " selection
        fi
        
        case "$selection" in
            0) log_warn "已退出"; exit 0 ;;
            1) ENV_NAME="production"; break ;;
            2) ENV_NAME="development"; break ;;
            *) echo "无效选择，请重试。" ;;
        esac
    done
    
    log_success "选择的环境: $ENV_NAME"
    echo ""
    
    export ENV_NAME
}


# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    select_environment
    echo "ENV_NAME=$ENV_NAME"
fi
