#!/bin/bash
# ==============================================================================
# 推送配置变量到 GitHub Environment Secrets
# 注意: 此脚本应被主脚本 source，依赖库由主脚本加载
# ==============================================================================

# 如果直接运行，加载依赖
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_SELF_DIR}/lib/common.sh"
    source "${_SELF_DIR}/lib/prompt.sh"
fi

# ------------------------------------------------------------------------------
# 主函数
# ------------------------------------------------------------------------------
push_config() {
    log_step "准备推送配置..."
    echo ""
    
    # 检查 gh CLI
    if ! command_exists gh; then
        die "GitHub CLI (gh) 未安装。请先安装: brew install gh"
    fi
    
    # 根据当前 git 分支推荐默认环境
    local current_branch=""
    local default_env=""
    local default_index=2 # 默认 development
    
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    
    case "$current_branch" in
        main|master) 
            default_env="production" 
            default_index=1
            ;;
        *) 
            default_env="development"
            default_index=2
            ;;
    esac
    
    if [[ -n "$default_env" ]]; then
        log_substep "检测到分支: $current_branch → 推荐环境: $default_env"
    fi
    
    echo ""
    echo "请选择目标环境:"
    echo "  1. production (vars.production.json)"
    echo "  2. development (vars.development.json)"
    echo "  0. 退出"
    echo ""
    
    local selection
    local env_name=""
    local vars_file=""
    
    while true; do
        read -p "选择 (0-2) [默认: $default_index]: " selection
        selection="${selection:-$default_index}"
        
        case "$selection" in
            0) log_warn "已退出"; exit 0 ;;
            1) 
                env_name="production"
                vars_file="vars.production.json"
                break 
                ;;
            2) 
                env_name="development"
                vars_file="vars.development.json"
                break 
                ;;
            *) echo "无效选择，请重试。" ;;
        esac
    done
    
    echo ""
    log_substep "目标环境: $env_name"
    log_substep "配置文件: $vars_file"
    echo ""
    
    # 检查配置文件是否存在
    if [[ ! -f "$vars_file" ]]; then
        log_error "配置文件 '$vars_file' 不存在!"
        echo "请复制示例文件并填入你的配置:"
        echo "  cp vars.${env_name}.example.json $vars_file"
        exit 1
    fi
    
    # 二次确认
    if ! confirm "确认将 '$vars_file' 推送到 '$env_name' 环境?" "y"; then
        log_warn "已取消"
        exit 0
    fi
    
    echo ""
    log_substep "正在推送配置..."
    
    if gh secret set VARS_JSON --env "$env_name" < "$vars_file"; then
        echo ""
        log_success "✅ 成功推送配置到 '$env_name' 环境!"
        
        # 提醒用户确保端口已开放
        echo ""
        print_separator
        echo "⚠️  重要提醒: 请确保防火墙已开放以下端口"
        print_separator
        
        # 尝试从配置文件读取端口
        if command_exists jq; then
            local vless_port=$(jq -r '.ports.vless // 443' "$vars_file")
            local h2_port=$(jq -r '.ports.hysteria2 // 443' "$vars_file")
            
            echo ""
            echo "   VLESS Reality: TCP 端口 $vless_port"
            echo "   Hysteria2:     UDP 端口 $h2_port"
            echo ""
            echo "如果防火墙规则未配置，请运行:"
            echo "   make setup-firewall"
        else
            echo ""
            echo "   请检查 vars.json 中配置的端口并确保防火墙规则已创建"
            echo "   运行 'make setup-firewall' 可快速创建规则"
        fi
        
        echo ""
    else
        echo ""
        log_error "❌ 推送失败"
        echo "可能原因:"
        echo "1. GitHub 环境 '$env_name' 不存在 (请先运行 make setup-wif)"
        echo "2. gh 登录失效 (运行 gh auth login)"
        echo "3. 权限不足"
        exit 1
    fi
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    push_config
fi
