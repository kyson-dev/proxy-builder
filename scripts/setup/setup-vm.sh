#!/bin/bash
# ==============================================================================
# 多环境 GCP 虚拟机配置脚本
# 支持 production 和 development 环境
# 
# 此脚本作为编排入口，调用虚拟机相关子模块完成配置并写入本地 .env
# ==============================================================================
set -e

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载通用库
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/prompt.sh"
source "${SCRIPT_DIR}/../lib/gcp.sh"

# 加载子模块
source "${SCRIPT_DIR}/shared/select-environment.sh"
source "${SCRIPT_DIR}/shared/select-project.sh"
source "${SCRIPT_DIR}/vm/select-vm.sh"
source "${SCRIPT_DIR}/vm/create-vm.sh"
source "${SCRIPT_DIR}/vm/ensure-oslogin.sh"

# ==============================================================================
# 前置检查
# ==============================================================================
check_prerequisites() {
    log_step "前置检查"
    
    if ! command_exists gcloud; then
        die "gcloud CLI 未安装"
    fi
    log_success "gcloud CLI 已安装"
    
    echo ""
}

# ==============================================================================
# 打印摘要
# ==============================================================================
print_summary() {
    local env_name="$1"
    local project="$2"
    local vm_name="$3"
    local vm_zone="$4"
    
    print_separator
    log_success "虚拟机配置完成 - '$env_name' 环境"
    print_separator
    echo ""
    echo "配置摘要 (已写入本地 .env.${env_name}):"
    echo "  环境:     $env_name"
    echo "  项目 ID:  $project"
    echo "  VM 名称:  $vm_name"
    echo "  VM 区域:  $vm_zone"
    echo ""
    echo "📋 下一步:"
    echo "   1. 运行仓库配置:   ./scripts/setup/setup-ar.sh"
    echo "   2. 推送至 GitHub:  ./scripts/setup/upload-env.sh"
    echo ""
}

# ==============================================================================
# 主流程
# ==============================================================================
main() {
    print_header "配置 GCP 虚拟机部署实例"
    
    # 前置检查
    check_prerequisites
    
    # Step 0: 选择环境
    select_environment
    
    # Step 1: 选择 GCP 项目
    select_gcp_project
    
    # Step 2: 选择或创建 VM
    select_vm "$PROJECT_ID" "$ENV_NAME"
    
    # Step 3: 确保 OS Login 启用
    ensure_oslogin "$PROJECT_ID" "$VM_NAME" "$VM_ZONE"
    
    # Step 4: 写入到本地环境配置
    local env_file="${SCRIPT_DIR}/../../.env.${ENV_NAME}"
    echo ""
    log_step "写入虚拟机参数至本地环境配置"
    update_env_file "$env_file" "GCP_VM_NAME" "$VM_NAME"
    update_env_file "$env_file" "GCP_VM_ZONE" "$VM_ZONE"
    echo ""
    
    # 打印摘要
    print_summary "$ENV_NAME" "$PROJECT_ID" "$VM_NAME" "$VM_ZONE"
}

# 运行主流程
main "$@"
