#!/bin/bash
# ==============================================================================
# Layer 2: VM 功能模块
# 职责: 完成虚拟机创建、服务账号绑定、OS Login 启用
# 接口: infra::create_vm <project_id> <vm_name> <zone> [machine_type] [disk_size] [disk_type] [network_tier] [is_spot]
#        infra::ensure_vm_oslogin <project_id> <vm_name> <zone>
# 依赖: lib/common.sh, lib/gcp.sh (由调用方预先加载)
# 无交互: 不调用任何 prompt_* / read 函数; 自包含，不 source 其它 setup 子文件
# ==============================================================================

# 防止重复加载
[[ -n "${_INFRA_VM_LOADED:-}" ]] && return 0
_INFRA_VM_LOADED=1

# ------------------------------------------------------------------------------
# 内部: 确保 SSH 防火墙规则存在（全项目共用）
# ------------------------------------------------------------------------------
_infra_vm_ensure_ssh_firewall() {
    local project="$1"
    local rule_name="allow-ssh"

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
# 内部: 创建 VM 专属服务账号
# ------------------------------------------------------------------------------
_infra_vm_create_service_account() {
    local project="$1"
    local sa_name="$2"

    local sa_email="${sa_name}@${project}.iam.gserviceaccount.com"

    if gcloud iam service-accounts describe "$sa_email" --project="$project" &>/dev/null; then
        log_substep "服务账号已存在: $sa_name"
        return 0
    fi

    log_substep "创建服务账号: $sa_name"

    gcloud iam service-accounts create "$sa_name" \
        --project="$project" \
        --display-name="VM Service Account - $sa_name"

    log_substep "为虚拟机服务账号授予日志与监控指标写入权限..."
    gcloud projects add-iam-policy-binding "$project" \
        --member="serviceAccount:${sa_email}" \
        --role="roles/logging.logWriter" \
        --quiet >/dev/null

    gcloud projects add-iam-policy-binding "$project" \
        --member="serviceAccount:${sa_email}" \
        --role="roles/monitoring.metricWriter" \
        --quiet > /dev/null

    # 授权从 Artifact Registry 拉取镜像（用于 docker compose pull）
    gcloud projects add-iam-policy-binding "$project" \
        --member="serviceAccount:${sa_email}" \
        --role="roles/artifactregistry.reader" \
        --quiet > /dev/null
}

# ------------------------------------------------------------------------------
# 内部: 创建 VM (核心函数)
# ------------------------------------------------------------------------------
_infra_vm_create_core() {
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

    if gcp_vm_exists "$vm_name" "$zone" "$project_id"; then
        log_substep "VM 已存在: ${vm_name}，跳过创建"
        export VM_NAME="$vm_name"
        export VM_ZONE="$zone"
        return 0
    fi

    # 1. 确保 SSH 防火墙规则存在
    _infra_vm_ensure_ssh_firewall "$project_id"

    # 2. 创建服务账号（名称与 VM 相同）
    _infra_vm_create_service_account "$project_id" "$vm_name"
    local sa_email="${vm_name}@${project_id}.iam.gserviceaccount.com"

    # 等待服务账号在 IAM 系统中传播
    log_substep "等待服务账号传播..."
    sleep 5

    # 3. 创建 VM
    _infra_vm_create_core "$project_id" "$vm_name" "$zone" "$machine_type" "$disk_size" "$disk_type" "$network_tier" "$is_spot" "$sa_email"

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
