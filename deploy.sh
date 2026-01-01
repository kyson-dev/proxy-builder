#!/bin/bash
# ==============================================================================
# 代理服务部署脚本 (S-UI 版本)
# 
# 此脚本作为编排入口，调用各个子模块完成部署
# ==============================================================================
set -e

echo "🚀 开始部署 S-UI 代理服务..."
echo ""

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

# 加载通用库（所有库都在此加载，子模块不再重复加载）
source "${SCRIPTS_DIR}/lib/common.sh"
source "${SCRIPTS_DIR}/lib/os.sh"
source "${SCRIPTS_DIR}/lib/docker.sh"

# 加载子模块
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
    # Step 1: 启用 BBR
    enable_bbr
    echo ""
    
    # Step 2: 检查并安装 Docker
    check_docker
    echo ""
    
    # Step 3: 检查并安装依赖
    check_dependencies
    echo ""
    
    # Step 4: 生成自签名证书 (用于 Hysteria2)
    generate_certs "./s-ui/cert"
    echo ""
    
    # Step 5: 启动服务
    start_services "docker-compose.yml"
    echo ""
    
    # Step 6: 健康检查
    health_check 5
}

# 运行主流程
main "$@"
