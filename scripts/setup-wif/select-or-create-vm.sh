#!/bin/bash
# ==============================================================================
# 选择或创建 VM
# 注意: 此脚本应被主脚本 source，依赖库由主脚本加载
# ==============================================================================

# 如果直接运行，加载依赖
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_SELF_DIR}/../lib/common.sh"
    source "${_SELF_DIR}/../lib/prompt.sh"
    source "${_SELF_DIR}/../lib/gcp.sh"
fi

# VM 预设配置 (使用普通变量，兼容 bash 3.x)
# Free Tier 预设
FREETIER_ZONE="us-west1-b"
FREETIER_MACHINE="e2-micro"
FREETIER_DISK_SIZE="30"
FREETIER_DISK_TYPE="pd-standard"
FREETIER_NETWORK_TIER="STANDARD"

# Spot 预设
SPOT_ZONE="us-central1-a"
SPOT_MACHINE="e2-micro"
SPOT_DISK_SIZE="10"
SPOT_DISK_TYPE="pd-standard"
SPOT_NETWORK_TIER="STANDARD"


# ------------------------------------------------------------------------------
# 创建 VM
# ------------------------------------------------------------------------------
create_vm() {
    local project="$1"
    local vm_name="$2"
    local zone="$3"
    local machine_type="$4"
    local disk_size="$5"
    local disk_type="$6"
    local network_tier="$7"
    local is_spot="${8:-false}"
    
    local provisioning_model="STANDARD"
    local maintenance_policy="MIGRATE"
    local extra_args=""
    
    if [[ "$is_spot" == "true" ]]; then
        provisioning_model="SPOT"
        maintenance_policy="TERMINATE"
        extra_args="--instance-termination-action=STOP"
    fi
    
    log_substep "创建 VM: $vm_name (区域: $zone)"
    
    gcloud compute instances create "$vm_name" \
        --project="$project" \
        --zone="$zone" \
        --machine-type="$machine_type" \
        --network-interface=network-tier="$network_tier",stack-type=IPV4_ONLY,subnet=default \
        --metadata=enable-oslogin=TRUE \
        --maintenance-policy="$maintenance_policy" \
        --provisioning-model="$provisioning_model" \
        $extra_args \
        --create-disk=auto-delete=yes,boot=yes,device-name="$vm_name",image=projects/debian-cloud/global/images/debian-12-bookworm-v20241210,mode=rw,size="$disk_size",type="$disk_type" \
        --no-shielded-secure-boot \
        --shielded-vtpm \
        --shielded-integrity-monitoring \
        --labels=goog-ec-src=vm_add-gcloud \
        --reservation-affinity=any
}

# ------------------------------------------------------------------------------
# 显示现有 VM 列表
# ------------------------------------------------------------------------------
display_vm_list() {
    local vm_list="$1"
    
    echo ""
    echo "现有 VM 实例:"
    
    local i=0
    while IFS=',' read -r name zone status; do
        local status_icon="⚪"
        [[ "$status" == "RUNNING" ]] && status_icon="🟢"
        [[ "$status" == "TERMINATED" ]] && status_icon="🔴"
        
        echo "  $((i+1)). $name"
        echo "      区域: $zone | 状态: $status_icon $status"
        ((i++))
    done <<< "$vm_list"
    
    echo "  0. 手动输入"
    echo ""
}

# ------------------------------------------------------------------------------
# 主函数
# ------------------------------------------------------------------------------
select_or_create_vm() {
    local project="${1:-$PROJECT_ID}"
    local env_name="${2:-$ENV_NAME}"
    
    if [[ -z "$project" ]]; then
        die "PROJECT_ID 未设置"
    fi
    
    log_step "Step 9: 选择或创建 VM ('$env_name' 环境)"
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
    fi
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
            create_new_vm_interactive "$project"
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
                if ! confirm "是否继续?"; then
                    continue
                fi
            fi
            break
        fi
        
        echo "无效选择，请重试。"
    done
    
    log_success "选择的 VM: $VM_NAME (区域: $VM_ZONE)"
    echo ""
    
    export VM_NAME VM_ZONE
}

# ------------------------------------------------------------------------------
# 创建新 VM 交互
# ------------------------------------------------------------------------------
create_new_vm_interactive() {
    local project="$1"
    
    echo ""
    echo "🆕 创建新 VM"
    echo ""
    echo "预设配置:"
    echo "  1. Google Free Tier (e2-micro, us-west1)"
    echo "     - 机器类型: e2-micro (0.25-2 vCPU, 1GB RAM)"
    echo "     - 磁盘: 30GB Standard"
    echo "     - 网络: 200GB/月免费 (STANDARD 模式)"
    echo "     - 费用: 免费 (在配额内)"
    echo ""
    echo "  2. 经济型 Spot 实例 (e2-micro, 可被抢占)"
    echo "     - 机器类型: e2-micro"
    echo "     - 磁盘: 10GB Standard"
    echo "     - 费用: ~\$5/月 (可能被回收)"
    echo ""
    echo "  3. 自定义配置"
    echo "  0. 返回"
    echo ""
    
    local preset_choice
    while true; do
        read -p "选择预设 (0-3): " preset_choice
        
        case $preset_choice in
            0)
                # 返回上级菜单，重新调用主函数
                select_or_create_vm "$project" "$ENV_NAME"
                return
                ;;
            1)
                local default_name="instance-$(date +%Y%m%d)"
                prompt_with_default "VM 名称" "$default_name"
                VM_NAME="$INPUT_VALUE"
                VM_ZONE="$FREETIER_ZONE"
                
                echo ""
                log_substep "创建 Free Tier VM..."
                create_vm "$project" "$VM_NAME" "$VM_ZONE" \
                    "$FREETIER_MACHINE" \
                    "$FREETIER_DISK_SIZE" \
                    "$FREETIER_DISK_TYPE" \
                    "$FREETIER_NETWORK_TIER" \
                    "false"
                log_success "VM 创建成功: $VM_NAME (区域: $VM_ZONE)"
                return
                ;;
            2)
                local default_name="spot-$(date +%Y%m%d)"
                prompt_with_default "VM 名称" "$default_name"
                VM_NAME="$INPUT_VALUE"
                VM_ZONE="$SPOT_ZONE"
                
                echo ""
                log_substep "创建 Spot VM..."
                create_vm "$project" "$VM_NAME" "$VM_ZONE" \
                    "$SPOT_MACHINE" \
                    "$SPOT_DISK_SIZE" \
                    "$SPOT_DISK_TYPE" \
                    "$SPOT_NETWORK_TIER" \
                    "true"
                log_warn "注意: Spot 实例可能随时被抢占"
                log_success "VM 创建成功: $VM_NAME (区域: $VM_ZONE)"
                return
                ;;
            3)
                local default_name="gcpvm-$(date +%Y%m%d)"
                prompt_with_default "VM 名称" "$default_name"
                VM_NAME="$INPUT_VALUE"
                
                prompt_with_default "区域 (如 us-central1-a)" "us-central1-a"
                VM_ZONE="$INPUT_VALUE"
                
                prompt_with_default "机器类型" "e2-micro"
                local machine_type="$INPUT_VALUE"
                
                prompt_with_default "磁盘大小 (GB)" "20"
                local disk_size="$INPUT_VALUE"
                
                prompt_with_default "网络层级 (STANDARD/PREMIUM)" "STANDARD"
                local network_tier="$INPUT_VALUE"
                
                echo ""
                log_substep "创建自定义 VM..."
                create_vm "$project" "$VM_NAME" "$VM_ZONE" \
                    "$machine_type" "$disk_size" "pd-standard" "$network_tier" "false"
                log_success "VM 创建成功: $VM_NAME (区域: $VM_ZONE)"
                return
                ;;
            *)
                echo "无效选择，请重试。"
                ;;
        esac
    done
}


# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    select_or_create_vm "$PROJECT_ID" "$ENV_NAME"
    echo "VM_NAME=$VM_NAME"
    echo "VM_ZONE=$VM_ZONE"
fi
