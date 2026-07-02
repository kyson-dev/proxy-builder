#!/bin/bash
# ==============================================================================
# 多环境 GCP 虚拟机配置脚本（重构版）
# 支持 production 和 development 环境
#
# 此脚本作为编排入口，通过 modules/infra-vm.sh 调用底层 VM 操作并写入本地 .env
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- 加载公共库 ---
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/prompt.sh"
source "${SCRIPT_DIR}/../lib/gcp.sh"

# --- 加载上下文解析器 + 功能模块 ---
source "${SCRIPT_DIR}/shared/resolve-context.sh"
source "${SCRIPT_DIR}/modules/infra-vm.sh"

# 预设常量（供交互模式使用）
FREETIER_ZONE="us-west1-b"
SPOT_ZONE="us-central1-a"

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
# 交互式收集 VM 配置参数
# 导出: VM_NAME, GCP_VM_ZONE, VM_MACHINE_TYPE, VM_DISK_SIZE, VM_DISK_TYPE,
#        VM_NETWORK_TIER, VM_IS_SPOT
# ==============================================================================
_collect_vm_params_interactive() {
    local env_name="$1"

    echo ""
    log_step "VM 参数配置"

    prompt_with_default "VM 实例名称" "proxy-vm-${env_name}"
    VM_NAME="$INPUT_VALUE"

    echo ""
    echo "VM 预设配置:"
    echo "  1. Google Free Tier (e2-micro, us-west1-b, 30GB)"
    echo "     - 费用: 免费 (在配额内)"
    echo "  2. Spot 实例        (e2-micro, us-central1-a, 10GB)"
    echo "     - 费用: ~\$5/月 (可能被回收)"
    echo "  3. 自定义配置"
    echo ""

    local preset_choice
    while true; do
        read -rp "选择预设 (1-3) [默认: 1]: " preset_choice
        preset_choice="${preset_choice:-1}"
        case "$preset_choice" in
            1)
                GCP_VM_ZONE="$FREETIER_ZONE"
                VM_MACHINE_TYPE="e2-micro"
                VM_DISK_SIZE="30"
                VM_DISK_TYPE="pd-standard"
                VM_NETWORK_TIER="STANDARD"
                VM_IS_SPOT="false"
                break
                ;;
            2)
                GCP_VM_ZONE="$SPOT_ZONE"
                VM_MACHINE_TYPE="e2-micro"
                VM_DISK_SIZE="10"
                VM_DISK_TYPE="pd-standard"
                VM_NETWORK_TIER="STANDARD"
                VM_IS_SPOT="true"
                break
                ;;
            3)
                prompt_with_default "GCE 区域 (如 us-central1-a)" "us-central1-a"
                GCP_VM_ZONE="$INPUT_VALUE"
                prompt_with_default "机器类型" "e2-micro"
                VM_MACHINE_TYPE="$INPUT_VALUE"
                prompt_with_default "磁盘大小 (GB)" "20"
                VM_DISK_SIZE="$INPUT_VALUE"
                prompt_with_default "网络层级 (STANDARD/PREMIUM)" "STANDARD"
                VM_NETWORK_TIER="$INPUT_VALUE"
                VM_DISK_TYPE="pd-standard"
                VM_IS_SPOT="false"
                break
                ;;
            *) echo "无效选择，请重试。" ;;
        esac
    done
}

# ==============================================================================
# 交互式选择或创建 VM
# ==============================================================================
_select_or_create_vm_interactive() {
    local project="$1"
    local env_name="$2"

    source "${SCRIPT_DIR}/vm/select-vm.sh"
    select_vm "$project" "$env_name"
    # select_vm 导出 VM_NAME 和 VM_ZONE（即 GCP_VM_ZONE）
    GCP_VM_ZONE="$VM_ZONE"
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
    echo "   1. 运行仓库配置:   make setup-ar"
    echo "   2. 推送至 GitHub:  make upload-env"
    echo "   （或使用一键部署: make setup-infra）"
    echo ""
}

# ==============================================================================
# 主流程
# ==============================================================================
main() {
    print_header "配置 GCP 虚拟机部署实例"

    check_prerequisites

    # 解析上下文（选择环境 + 项目）
    resolve_context

    # 交互式选择或创建 VM（含 VM 参数采集）
    _select_or_create_vm_interactive "$PROJECT_ID" "$ENV_NAME"

    # 确保 OS Login 启用（通过 infra-vm.sh 的无交互函数）
    infra::ensure_vm_oslogin "$PROJECT_ID" "$VM_NAME" "$GCP_VM_ZONE"

    # 写入本地环境配置
    local env_file="${SCRIPT_DIR}/../../.env.${ENV_NAME}"
    echo ""
    log_step "写入虚拟机参数至本地环境配置"
    update_env_file "$env_file" "GCP_VM_NAME" "$VM_NAME"
    update_env_file "$env_file" "GCP_VM_ZONE" "$GCP_VM_ZONE"
    echo ""

    print_summary "$ENV_NAME" "$PROJECT_ID" "$VM_NAME" "$GCP_VM_ZONE"
}

main "$@"
