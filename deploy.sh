#!/bin/bash
# ==============================================================================
# 代理服务部署脚本 (Sing-box 原生版本)
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
source "${SCRIPTS_DIR}/deploy/build-config.sh"
source "${SCRIPTS_DIR}/deploy/start-services.sh"
source "${SCRIPTS_DIR}/deploy/health-check.sh"

# ==============================================================================
# 主流程
# ==============================================================================
main() {
    local start_time=$(date +%s)
    
    print_header "部署 Sing-box 代理服务"

    # 1. 初始化完整环境 (补充默认路径并写入 .env)
    init_env "${SCRIPT_DIR}/.env"

    # 2. 验证基础配置 (REALITY_PRIVATE_KEY 等核心参数)
    validate_env "${SCRIPT_DIR}/.env"
    

    
    # Step 1: 初始化数据目录
    init_data_dir
    echo ""
    
    # Step 2: 检查并安装依赖 (jq, openssl 等，后续步骤需要)
    check_dependencies
    echo ""
    
    # Step 3: 启用 BBR
    enable_bbr
    echo ""
    
    # Step 4: 检查并安装 Docker
    check_docker
    echo ""
    
    # Step 5: 生成自签名证书
    generate_certs "${SING_BOX_DATA_DIR}/cert"
    echo ""

    # Step 6: 生成最终的 config.json
    build_config
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
