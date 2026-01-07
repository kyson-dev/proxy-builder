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

# 加载通用库
source "${SCRIPTS_DIR}/lib/common.sh"
source "${SCRIPTS_DIR}/lib/os.sh"
source "${SCRIPTS_DIR}/lib/docker.sh"

# 加载子模块
source "${SCRIPTS_DIR}/deploy/validate-env.sh"
source "${SCRIPTS_DIR}/deploy/init-env.sh"
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

    # 1. 初始化完整环境 (补充默认路径并写入 .env)
    init_env "${SCRIPT_DIR}/.env"

    # 2. 验证基础配置 (PANEL_DOMAIN)
    validate_env "${SCRIPT_DIR}/.env"
    

    
    # Step 1: 初始化数据目录
    init_data_dir
    echo ""
    
    # Step 2: 启用 BBR
    enable_bbr
    echo ""
    
    # Step 3: 检查并安装 Docker
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
