#!/bin/bash
# ==============================================================================
# 多环境 GCP 虚拟机配置脚本（重构版）
# 支持 production 和 development 环境
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# --- 加载公共库 ---
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/prompt.sh"
source "${SCRIPT_DIR}/../lib/gcp.sh"

# --- 加载系统执行层 ---
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

    prompt_with_default "VM 实例名称" "proxy-vm-$(date +%Y%m%d)"
    VM_NAME="$INPUT_VALUE"

    echo ""
    echo "VM 预设配置:"
    echo "  1. Google Free Tier (e2-micro, us-west1-b, 30GB)"
    echo "     - 费用: 免费 (在配额内)"
    echo "  2. Spot 实例        (e2-micro, us-central1-a, 10GB)"
    echo "     - 费用: ~\$5/月 (可能被回收)，网络层级为 STANDARD"
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

    # 1. 检测非交互模式条件
    local is_non_interactive=false
    if [[ "${CI:-}" == "true" ]] || [[ "${NON_INTERACTIVE:-}" == "true" ]]; then
        is_non_interactive=true
    fi

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --non-interactive) is_non_interactive=true ;;
        esac
        shift
    done

    # 2. 确定环境
    if [[ "$is_non_interactive" == "true" ]]; then
        if [[ -z "${ENV_NAME:-}" ]]; then
            die "非交互模式错误: 必须指定环境变量 ENV_NAME (production 或 development)"
        fi
    else
        source "${SCRIPT_DIR}/shared/select-environment.sh"
        select_environment
    fi

    local env_file="${PROJECT_ROOT}/.env.${ENV_NAME}"

    # 3. Project ID 只读本地 .env 文件（只能由 setup-wif.sh 写入）
    local env_project_id=""
    if [[ -f "$env_file" ]]; then
        env_project_id=$(grep "^[[:space:]]*GCP_PROJECT_ID=" "$env_file" | cut -d'=' -f2- | xargs 2>/dev/null || echo "")
    fi
    if [[ -z "$env_project_id" ]]; then
        die "在本地环境配置 '.env.${ENV_NAME}' 中没有找到 GCP_PROJECT_ID，请先执行: make setup-wif"
    fi
    PROJECT_ID="$env_project_id"
    log_success "检测并复用项目环境: $PROJECT_ID"

    # 4. 确定 VM 参数并创建/复用
    local sa_name="proxy-vm-sa"
    if [[ "$is_non_interactive" == "true" ]]; then
        VM_NAME="${VM_NAME:-proxy-vm-$(date +%Y%m%d)}"
        GCP_VM_ZONE="${GCP_VM_ZONE:-us-west1-b}"
        VM_MACHINE_TYPE="${VM_MACHINE_TYPE:-e2-micro}"
        VM_DISK_SIZE="${VM_DISK_SIZE:-10}"
        VM_DISK_TYPE="${VM_DISK_TYPE:-pd-standard}"
        VM_NETWORK_TIER="${VM_NETWORK_TIER:-STANDARD}"
        VM_IS_SPOT="${VM_IS_SPOT:-false}"

        infra::create_vm \
            "$PROJECT_ID" "$VM_NAME" "$GCP_VM_ZONE" "$sa_name" \
            "$VM_MACHINE_TYPE" "$VM_DISK_SIZE" "$VM_DISK_TYPE" "$VM_NETWORK_TIER" "$VM_IS_SPOT"
    else
        source "${SCRIPT_DIR}/vm/select-vm.sh"
        select_vm "$PROJECT_ID" "$ENV_NAME"
        GCP_VM_ZONE="$VM_ZONE"

        if [[ -z "$VM_NAME" ]]; then
            # 用户选择了创建新 VM
            _collect_vm_params_interactive "$ENV_NAME"
            infra::create_vm \
                "$PROJECT_ID" "$VM_NAME" "$GCP_VM_ZONE" "$sa_name" \
                "$VM_MACHINE_TYPE" "$VM_DISK_SIZE" "$VM_DISK_TYPE" "$VM_NETWORK_TIER" "$VM_IS_SPOT"
        else
            # 用户选择了已存在的 VM：展示当前绑定的服务账号，不做校验
            local vm_sa_email
            vm_sa_email=$(gcp_get_vm_service_account "$VM_NAME" "$GCP_VM_ZONE" "$PROJECT_ID")
            if [[ -n "$vm_sa_email" ]]; then
                log_substep "当前服务账号: $vm_sa_email"
            else
                log_warn "该 VM 未绑定服务账号"
            fi
        fi
    fi

    # 5. 确保 OS Login 启用
    infra::ensure_vm_oslogin "$PROJECT_ID" "$VM_NAME" "$GCP_VM_ZONE"

    # 6. 写入本地环境配置
    echo ""
    log_step "写入虚拟机参数至本地环境配置"
    update_env_file "$env_file" "GCP_VM_NAME" "$VM_NAME"
    update_env_file "$env_file" "GCP_VM_ZONE" "$GCP_VM_ZONE"
    echo ""

    print_summary "$ENV_NAME" "$PROJECT_ID" "$VM_NAME" "$GCP_VM_ZONE"
}

main "$@"
