#!/bin/bash
# ==============================================================================
# 代理服务部署脚本 (S-UI 版本)
# 
# 此脚本只负责部署，版本管理由 CD 处理
# ==============================================================================
set -e

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

# 加载环境变量文件（如果存在）
if [ -f "${SCRIPT_DIR}/.env" ]; then
    echo "📝 加载配置文件: .env"
    set -a  # 自动导出所有变量
    source "${SCRIPT_DIR}/.env"
    set +a
else
    echo "⚠️  未找到 .env 文件，使用默认配置"
    echo "   提示: 复制 .env.example 为 .env 并填写配置"
fi

# 数据根目录
export DATA_ROOT="${DATA_ROOT:-${HOME}/data}"

# 检查必需的环境变量
if [ -z "$PANEL_DOMAIN" ]; then
    echo "❌ 错误: 未设置 PANEL_DOMAIN 环境变量"
    echo "   请在 .env 文件中设置 PANEL_DOMAIN=your-domain.com"
    echo "   或运行: export PANEL_DOMAIN=your-domain.com"
    exit 1
fi

# 加载通用库
source "${SCRIPTS_DIR}/lib/common.sh"
source "${SCRIPTS_DIR}/lib/os.sh"
source "${SCRIPTS_DIR}/lib/docker.sh"

# 加载子模块
source "${SCRIPTS_DIR}/deploy/init-data-dir.sh"
source "${SCRIPTS_DIR}/deploy/enable-bbr.sh"
source "${SCRIPTS_DIR}/deploy/install-docker.sh"
source "${SCRIPTS_DIR}/deploy/install-dependencies.sh"
source "${SCRIPTS_DIR}/deploy/generate-certs.sh"
source "${SCRIPTS_DIR}/deploy/start-services.sh"
source "${SCRIPTS_DIR}/deploy/health-check.sh"

# ==============================================================================
# 主流程
# ==============================================================================
main() {
    local start_time=$(date +%s)
    
    print_header "部署 S-UI 代理服务"
    
    # Step 1: 初始化数据目录
    init_data_dir
    echo ""
    
    # Step 3: 启用 BBR
    enable_bbr
    echo ""
    
    # Step 4: 检查并安装 Docker
    check_docker
    echo ""
    
    # Step 5: 检查并安装依赖
    check_dependencies
    echo ""
    
    # Step 6: 生成自签名证书
    generate_certs "${S_UI_DATA_DIR}/cert"
    echo ""
    
    # Step 7: 启动服务
    start_services "docker-compose.yml"
    echo ""
    
    # Step 8: 健康检查
    if health_check 5; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        echo ""
        print_separator
        log_success "部署成功！耗时: ${duration}s"
        print_separator
        exit 0
    else
        echo ""
        log_error "健康检查失败"
        exit 1
    fi
}

main "$@"
