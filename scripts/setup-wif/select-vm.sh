#!/bin/bash
# ==============================================================================
# 选择现有 VM
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
# 主函数：选择 VM
# ------------------------------------------------------------------------------
select_vm() {
    local project="${1:-$PROJECT_ID}"
    local env_name="${2:-$ENV_NAME}"
    
    if [[ -z "$project" ]]; then
        die "PROJECT_ID 未设置"
    fi
    
    log_step "Step 9: 选择 VM ('$env_name' 环境)"
    echo ""
    
    log_substep "正在获取 VM 列表..."
    local vm_list
    vm_list=$(gcp_list_vms "$project")
    
    # 解析 VM 列表到数组
    local vm_names=()
    local vm_zones=()
    local vm_statuses=()
    local vm_count=0
    
    if [[ -n "$vm_list" ]]; then
        while IFS=',' read -r name zone status; do
            vm_names+=("$name")
            vm_zones+=("$zone")
            vm_statuses+=("$status")
            ((vm_count++))
        done <<< "$vm_list"
    fi
    
    # 显示菜单：所有 VM + 创建新 VM + 退出
    echo ""
    local default_vm_index=""
    if [[ $vm_count -eq 0 ]]; then
        log_warn "项目中没有现有 VM 实例"
        echo ""
        echo "请先创建 VM:"
        echo "  1. 🆕 创建新 VM"
        echo "  0. 退出"
        echo ""
        
        local choice
        read -p "选择 (0-1): " choice
        case "$choice" in
            1) 
                # 调用创建 VM 脚本
                create_vm_interactive "$project"
                ;;
            *) 
                log_warn "已退出"
                exit 0 
                ;;
        esac
    else
        echo "现有 VM 实例:"
        local i
        for ((i=0; i<vm_count; i++)); do
            local status_icon="⚪"
            [[ "${vm_statuses[$i]}" == "RUNNING" ]] && status_icon="🟢"
            [[ "${vm_statuses[$i]}" == "TERMINATED" ]] && status_icon="🔴"
            
            # 找第一个 RUNNING 的 VM 作为默认
            if [[ -z "$default_vm_index" ]] && [[ "${vm_statuses[$i]}" == "RUNNING" ]]; then
                default_vm_index=$((i+1))
            fi
            
            echo "  $((i+1)). ${vm_names[$i]}"
            echo "      区域: ${vm_zones[$i]} | 状态: $status_icon ${vm_statuses[$i]}"
        done
        echo ""
        echo "  $((vm_count+1)). 🆕 创建新 VM"
        echo "  0. 退出"
        echo ""
        
        local selection
        while true; do
            if [[ -n "$default_vm_index" ]]; then
                read -p "选择 (0-$((vm_count+1))) [默认: $default_vm_index]: " selection
                selection="${selection:-$default_vm_index}"
            else
                read -p "选择 (0-$((vm_count+1))): " selection
            fi
            
            # 退出
            if [[ "$selection" == "0" ]]; then
                log_warn "已退出"
                exit 0
            fi
            
            # 创建新 VM
            if [[ "$selection" == "$((vm_count+1))" ]]; then
                create_vm_interactive "$project"
                break
            fi
            
            # 选择现有 VM
            if [[ "$selection" =~ ^[0-9]+$ ]] && \
               [[ "$selection" -ge 1 ]] && \
               [[ "$selection" -le "$vm_count" ]]; then
                VM_NAME="${vm_names[$((selection-1))]}"
                VM_ZONE="${vm_zones[$((selection-1))]}"
                local vm_status="${vm_statuses[$((selection-1))]}"
                
                if [[ "$vm_status" != "RUNNING" ]]; then
                    log_warn "VM '$VM_NAME' 未运行 (状态: $vm_status)"
                    if ! confirm "是否继续?" "y"; then
                        continue
                    fi
                fi
                break
            fi
            
            echo "无效选择，请重试。"
        done
    fi
    
    log_success "选择的 VM: $VM_NAME (区域: $VM_ZONE)"
    echo ""
    
    export VM_NAME VM_ZONE
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    select_vm "$PROJECT_ID" "$ENV_NAME"
    echo "VM_NAME=$VM_NAME"
    echo "VM_ZONE=$VM_ZONE"
fi
