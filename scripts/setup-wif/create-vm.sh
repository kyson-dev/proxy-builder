#!/bin/bash
# ==============================================================================
# 创建新 VM（包含服务账号和防火墙规则）
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
# 确保 SSH 防火墙规则存在（全项目共用）
# ------------------------------------------------------------------------------
ensure_ssh_firewall() {
    local project="$1"
    local rule_name="allow-ssh"
    
    # 检查规则是否已存在
    if gcloud compute firewall-rules describe "$rule_name" --project="$project" &>/dev/null; then
        log_substep "SSH 防火墙规则已存在: $rule_name"
        return 0
    fi
    
    log_substep "创建 SSH 防火墙规则: $rule_name"
    
    gcloud compute firewall-rules create "$rule_name" \
        --project="$project" \
        --direction=INGRESS \
        --priority=1000 \
        --network=default \
        --allow=tcp:22 \
        --source-ranges=0.0.0.0/0 \
        --description="Allow SSH access to all instances"

}

# ------------------------------------------------------------------------------
# 创建 VM 专属服务账号
# ------------------------------------------------------------------------------
create_vm_service_account() {
    local project="$1"
    local sa_name="$2"
    
    local sa_email="${sa_name}@${project}.iam.gserviceaccount.com"
    
    # 检查服务账号是否已存在
    if gcloud iam service-accounts describe "$sa_email" --project="$project" &>/dev/null; then
        log_substep "服务账号已存在: $sa_name"
        return 0
    fi
    
    log_substep "创建服务账号: $sa_name"
    
    gcloud iam service-accounts create "$sa_name" \
        --project="$project" \
        --display-name="VM Service Account - $sa_name"
}

# ------------------------------------------------------------------------------
# 创建 VM (核心函数)
# ------------------------------------------------------------------------------
create_vm_core() {
    local project="$1"
    local vm_name="$2"
    local zone="$3"
    local machine_type="$4"
    local disk_size="$5"
    local disk_type="$6"
    local network_tier="$7"
    local is_spot="${8:-false}"
    local sa_email="$9"
    
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
        --network-interface=network-tier="$network_tier",stack-type=IPV4_ONLY,subnet=default,address= \
        --metadata=enable-oslogin=TRUE \
        --maintenance-policy="$maintenance_policy" \
        --provisioning-model="$provisioning_model" \
        $extra_args \
        --service-account="$sa_email" \
        --scopes=https://www.googleapis.com/auth/cloud-platform \
        --create-disk=auto-delete=yes,boot=yes,device-name="$vm_name",image=projects/debian-cloud/global/images/debian-12-bookworm-v20241210,mode=rw,size="$disk_size",type="$disk_type" \
        --no-shielded-secure-boot \
        --shielded-vtpm \
        --shielded-integrity-monitoring \
        --labels=goog-ec-src=vm_add-gcloud \
        --reservation-affinity=any
}

# ------------------------------------------------------------------------------
# 创建 VM 交互流程
# ------------------------------------------------------------------------------
create_vm_interactive() {
    local project="${1:-$PROJECT_ID}"
    
    if [[ -z "$project" ]]; then
        die "PROJECT_ID 未设置"
    fi
    
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
                return 1  # 返回上级
                ;;
            1)
                local default_name="instance-$(date +%Y%m%d)"
                prompt_with_default "VM 名称" "$default_name"
                VM_NAME="$INPUT_VALUE"
                VM_ZONE="$FREETIER_ZONE"
                
                echo ""
                create_vm_with_sa "$project" "$VM_NAME" "$VM_ZONE" \
                    "$FREETIER_MACHINE" "$FREETIER_DISK_SIZE" "$FREETIER_DISK_TYPE" \
                    "$FREETIER_NETWORK_TIER" "false"
                return 0
                ;;
            2)
                local default_name="spot-$(date +%Y%m%d)"
                prompt_with_default "VM 名称" "$default_name"
                VM_NAME="$INPUT_VALUE"
                VM_ZONE="$SPOT_ZONE"
                
                echo ""
                create_vm_with_sa "$project" "$VM_NAME" "$VM_ZONE" \
                    "$SPOT_MACHINE" "$SPOT_DISK_SIZE" "$SPOT_DISK_TYPE" \
                    "$SPOT_NETWORK_TIER" "true"
                log_warn "注意: Spot 实例可能随时被抢占"
                return 0
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
                create_vm_with_sa "$project" "$VM_NAME" "$VM_ZONE" \
                    "$machine_type" "$disk_size" "pd-standard" "$network_tier" "false"
                return 0
                ;;
            *)
                echo "无效选择，请重试。"
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# 创建 VM（包含服务账号和防火墙规则）
# ------------------------------------------------------------------------------
create_vm_with_sa() {
    local project="$1"
    local vm_name="$2"
    local zone="$3"
    local machine_type="$4"
    local disk_size="$5"
    local disk_type="$6"
    local network_tier="$7"
    local is_spot="$8"
    
    # 1. 确保 SSH 防火墙规则存在
    ensure_ssh_firewall "$project"
    
    # 2. 创建服务账号（名称与 VM 相同）
    create_vm_service_account "$project" "$vm_name"
    local sa_email="${vm_name}@${project}.iam.gserviceaccount.com"
    
    # 等待服务账号在 IAM 系统中传播
    log_substep "等待服务账号传播..."
    sleep 5
    
    # 3. 创建 VM
    create_vm_core "$project" "$vm_name" "$zone" "$machine_type" "$disk_size" "$disk_type" "$network_tier" "$is_spot" "$sa_email"
    
    echo ""
    log_success "VM 创建成功: $vm_name"
    log_substep "区域: $zone"
    log_substep "服务账号: $sa_email"
    log_substep "SSH 防火墙: allow-ssh (端口 22)"
    echo ""
    echo "💡 提示: 其他端口（如 443）将在部署时根据配置自动开放"
    echo ""
    
    export VM_NAME="$vm_name"
    export VM_ZONE="$zone"
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    create_vm_interactive "$PROJECT_ID"
    echo "VM_NAME=$VM_NAME"
    echo "VM_ZONE=$VM_ZONE"
fi
