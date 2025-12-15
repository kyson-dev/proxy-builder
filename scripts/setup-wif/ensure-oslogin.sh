#!/bin/bash
# ==============================================================================
# 确保 VM 启用 OS Login
# 注意: 此脚本应被主脚本 source，依赖库由主脚本加载
# ==============================================================================

# 如果直接运行，加载依赖
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_SELF_DIR}/../lib/common.sh"
    source "${_SELF_DIR}/../lib/prompt.sh"
    source "${_SELF_DIR}/../lib/gcp.sh"
fi

# ------------------------------------------------------------------------------
# 主函数
# ------------------------------------------------------------------------------
ensure_oslogin() {
    local project="${1:-$PROJECT_ID}"
    local vm_name="${2:-$VM_NAME}"
    local vm_zone="${3:-$VM_ZONE}"
    
    if [[ -z "$project" ]] || [[ -z "$vm_name" ]] || [[ -z "$vm_zone" ]]; then
        die "缺少必要参数: PROJECT_ID, VM_NAME, VM_ZONE"
    fi
    
    log_step "Step 10: 检查 OS Login 配置"
    
    # 使用 timeout 避免 gcloud 命令卡住 (如果有 timeout 命令)
    local timeout_cmd=""
    if command -v timeout &>/dev/null; then
        timeout_cmd="timeout 30"
    elif command -v gtimeout &>/dev/null; then
        timeout_cmd="gtimeout 30"  # macOS with coreutils
    fi
    
    log_substep "检查 VM $vm_name 的 OS Login 状态..."
    
    local status=""
    if [[ -n "$timeout_cmd" ]]; then
        status=$($timeout_cmd gcloud compute instances describe "$vm_name" \
            --zone "$vm_zone" \
            --project "$project" \
            --format="get(metadata.items[key=enable-oslogin].value)" 2>/dev/null) || true
    else
        status=$(gcloud compute instances describe "$vm_name" \
            --zone "$vm_zone" \
            --project "$project" \
            --format="get(metadata.items[key=enable-oslogin].value)" 2>/dev/null) || true
    fi
    
    # 检查是否启用 (处理大小写)
    if [[ "$status" == "TRUE" ]] || [[ "$status" == "true" ]] || [[ "$status" == "True" ]]; then
        log_success "OS Login 已在 $vm_name 上启用"
    else
        log_warn "OS Login 未在 $vm_name 上启用 (当前值: ${status:-未设置})"
        
        if confirm "是否现在启用 OS Login?" "y"; then
            log_substep "正在启用 OS Login..."
            if gcloud compute instances add-metadata "$vm_name" \
                --zone "$vm_zone" \
                --project "$project" \
                --metadata enable-oslogin=TRUE 2>/dev/null; then
                log_success "OS Login 已启用"
            else
                log_warn "启用 OS Login 失败，可能是网络问题。请稍后手动启用。"
            fi
        else
            log_warn "跳过 OS Login 配置。部署可能会失败。"
        fi
    fi
    
    echo ""
}


# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    ensure_oslogin "$PROJECT_ID" "$VM_NAME" "$VM_ZONE"
fi
