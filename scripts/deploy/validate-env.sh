#!/bin/bash
# ==============================================================================
# 加载并验证环境变量
# 
# 功能:
# 1. 加载 .env 文件
# 2. 验证必填变量是否存在
# ==============================================================================

validate_env() {
    local env_file="${1:-.env}"
    
    # 1. 加载 .env 文件
    if [ -f "$env_file" ]; then
        echo "📝 加载配置文件: $env_file"
        set -a
        source "$env_file"
        set +a
    else
        echo "⚠️  警告: 未找到 $env_file 文件"
    fi

    # 2. 定义必填变量列表
    local required_vars=(
        "PANEL_DOMAIN"
        "DATA_ROOT"
        "S_UI_DATA_DIR"
        "CADDY_DATA_DIR"
    )

    # 3. 检查必填变量
    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done

    # 4. 如果有缺失变量，报错退出
    if [ ${#missing_vars[@]} -gt 0 ]; then
        echo ""
        echo "❌ 错误: 缺少以下必需的环境变量:"
        for var in "${missing_vars[@]}"; do
            echo "   - $var"
        done
        echo ""
        echo "请确保 .env 文件包含以上所有配置。"
        exit 1
    fi

    # 5. 输出当前配置（可选，用于调试）
    # echo "✅ 环境配置已加载"
    # echo "   域名: $PANEL_DOMAIN"
    # echo "   数据根目录: $DATA_ROOT"
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    validate_env
fi
