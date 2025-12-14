#!/bin/bash
# ==============================================================================
# 代理服务部署脚本
# 
# 此脚本作为编排入口，调用各个子模块完成部署
# ==============================================================================
set -e

echo "🚀 开始部署代理服务..."
echo ""

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

# 加载通用库（所有库都在此加载，子模块不再重复加载）
source "${SCRIPTS_DIR}/lib/common.sh"
source "${SCRIPTS_DIR}/lib/os.sh"

# 加载子模块
source "${SCRIPTS_DIR}/deploy/enable-bbr.sh"
source "${SCRIPTS_DIR}/deploy/install-docker.sh"
source "${SCRIPTS_DIR}/deploy/install-dependencies.sh"
source "${SCRIPTS_DIR}/deploy/parse-config.sh"
source "${SCRIPTS_DIR}/deploy/configure-firewall.sh"
source "${SCRIPTS_DIR}/deploy/generate-certs.sh"
source "${SCRIPTS_DIR}/deploy/start-services.sh"
source "${SCRIPTS_DIR}/deploy/health-check.sh"

# ==============================================================================
# 主流程
# ==============================================================================
main() {
    # Step 0: 启用 BBR
    enable_bbr
    echo ""
    
    # Step 1: 检查并安装 Docker
    check_docker
    echo ""
    
    # Step 2: 检查并安装依赖
    check_dependencies
    echo ""
    
    # Step 3: 解析配置文件
    parse_config "vars.json"
    echo ""
    
    # Step 4: 配置防火墙规则（根据端口动态创建）
    configure_firewall
    echo ""
    
    # Step 5: 生成自签名证书
    generate_certs "./sing-box/certs"
    echo ""
    
    # Step 6: 启动服务
    start_services "docker-compose.yml"
    echo ""
    
    # Step 7: 健康检查
    health_check 5
}


# 运行主流程
main "$@"
