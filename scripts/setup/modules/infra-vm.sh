#!/bin/bash
# ==============================================================================
# Layer 2: VM 功能模块
# 职责: 编排 VM 相关子模块，完成虚拟机创建、服务账号绑定、OS Login 启用
# 接口: infra::create_vm <project_id> <vm_name> <zone> [machine_type] [disk_size] [disk_type] [network_tier] [is_spot]
#        infra::ensure_vm_oslogin <project_id> <vm_name> <zone>
# 依赖: lib/common.sh, lib/gcp.sh, vm/create-vm.sh, vm/ensure-oslogin.sh
# 无交互: 不调用任何 prompt_* / read 函数
# ==============================================================================

# 防止重复加载
[[ -n "${_INFRA_VM_LOADED:-}" ]] && return 0
_INFRA_VM_LOADED=1

# 加载子模块
_INFRA_VM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_INFRA_VM_DIR}/../vm/create-vm.sh"
source "${_INFRA_VM_DIR}/../vm/ensure-oslogin.sh"

# ==============================================================================
# infra::create_vm — 创建 VM（含服务账号和 SSH 防火墙）
# ==============================================================================
# 参数:
#   $1  project_id    GCP 项目 ID（必须）
#   $2  vm_name       VM 实例名称（必须）
#   $3  zone          GCE 区域，如 us-west1-b（必须）
#   $4  machine_type  机器类型（可选，默认 e2-micro）
#   $5  disk_size     磁盘大小 GB（可选，默认 20）
#   $6  disk_type     磁盘类型（可选，默认 pd-standard）
#   $7  network_tier  网络层级（可选，默认 STANDARD）
#   $8  is_spot       是否为 Spot 实例，true/false（可选，默认 false）
#
# 导出:
#   VM_NAME   VM 实例名称
#   VM_ZONE   VM 所在区域
# ==============================================================================
infra::create_vm() {
    local project_id="${1:?infra::create_vm: project_id 不能为空}"
    local vm_name="${2:?infra::create_vm: vm_name 不能为空}"
    local zone="${3:?infra::create_vm: zone 不能为空}"
    local machine_type="${4:-e2-micro}"
    local disk_size="${5:-20}"
    local disk_type="${6:-pd-standard}"
    local network_tier="${7:-STANDARD}"
    local is_spot="${8:-false}"

    log_step "VM 创建: $vm_name (区域: $zone, 机器: $machine_type)"

    # 检查 VM 是否已存在
    if gcp_vm_exists "$vm_name" "$zone" "$project_id"; then
        log_substep "VM 已存在: $vm_name，跳过创建"
        export VM_NAME="$vm_name"
        export VM_ZONE="$zone"
        return 0
    fi

    # 调用 vm/create-vm.sh 中的纯操作函数
    create_vm_with_sa \
        "$project_id" \
        "$vm_name" \
        "$zone" \
        "$machine_type" \
        "$disk_size" \
        "$disk_type" \
        "$network_tier" \
        "$is_spot"

    # VM_NAME 和 VM_ZONE 已由 create_vm_with_sa 导出
}

# ==============================================================================
# infra::ensure_vm_oslogin — 确保 VM 启用 OS Login
# ==============================================================================
# 参数:
#   $1  project_id  GCP 项目 ID（必须）
#   $2  vm_name     VM 实例名称（必须）
#   $3  zone        GCE 区域（必须）
# ==============================================================================
infra::ensure_vm_oslogin() {
    local project_id="${1:?infra::ensure_vm_oslogin: project_id 不能为空}"
    local vm_name="${2:?infra::ensure_vm_oslogin: vm_name 不能为空}"
    local zone="${3:?infra::ensure_vm_oslogin: zone 不能为空}"

    log_step "OS Login 检查: $vm_name"

    if gcp_oslogin_enabled "$vm_name" "$zone" "$project_id"; then
        log_success "OS Login 已启用: $vm_name"
        return 0
    fi

    log_substep "启用 OS Login..."
    if gcp_enable_oslogin "$vm_name" "$zone" "$project_id"; then
        log_success "OS Login 已启用: $vm_name"
    else
        log_warn "启用 OS Login 失败，请手动检查。部署时可能需要处理 SSH 连接问题。"
    fi

    echo ""
}
