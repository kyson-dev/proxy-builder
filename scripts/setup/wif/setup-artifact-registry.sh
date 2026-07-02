#!/bin/bash
# ==============================================================================
# 创建 Artifact Registry Docker 仓库
# 注意: 此脚本应被主脚本 source，依赖库由主脚本加载
# ==============================================================================

# 如果直接运行，加载依赖
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_SELF_DIR}/../../lib/common.sh"
    source "${_SELF_DIR}/../../lib/prompt.sh"
    source "${_SELF_DIR}/../../lib/gcp.sh"
fi

# ------------------------------------------------------------------------------
# 从 zone 派生 region（去掉最后一段，如 us-west1-b → us-west1）
# ------------------------------------------------------------------------------
_ar_zone_to_region() {
    local zone="$1"
    echo "${zone%-*}"
}

# ------------------------------------------------------------------------------
# 检查 AR 仓库是否存在
# ------------------------------------------------------------------------------
_ar_repo_exists() {
    local project="$1"
    local location="$2"
    local repo="$3"
    gcloud artifacts repositories describe "$repo" \
        --project="$project" \
        --location="$location" &>/dev/null
}

# ------------------------------------------------------------------------------
# 创建或选择 AR Docker 仓库（交互式）
# ------------------------------------------------------------------------------
setup_artifact_registry() {
    local project="${1:-$PROJECT_ID}"
    local zone="${2:-$VM_ZONE}"

    if [[ -z "$project" ]]; then
        die "PROJECT_ID 未设置"
    fi

    log_step "设置 Artifact Registry"

    # 1. 尝试获取现有 Docker 仓库列表
    log_substep "正在获取 Artifact Registry 仓库列表..."
    local repo_list
    repo_list=$(gcloud artifacts repositories list \
        --project="$project" \
        --filter="format=docker" \
        --format="csv[no-heading](name,location)" 2>/dev/null || echo "")

    local repo_names=()
    local repo_locations=()
    local repo_count=0

    if [[ -n "$repo_list" ]]; then
        while IFS=',' read -r name location; do
            if [[ -n "$name" ]]; then
                # 提取仓库短名称，以防返回完整资源路径
                local base_name
                base_name=$(basename "$name")
                repo_names+=("$base_name")
                repo_locations+=("$location")
                ((repo_count++))
            fi
        done <<< "$repo_list"
    fi

    local selected_name=""
    local selected_location=""

    # 2. 交互式选择或新建
    if [[ $repo_count -gt 0 ]]; then
        echo ""
        echo "现有 Docker 仓库实例:"
        local i
        for ((i=0; i<repo_count; i++)); do
            echo "  $((i+1)). ${repo_names[$i]} (区域: ${repo_locations[$i]})"
        done
        echo ""
        echo "  $((repo_count+1)). 🆕 创建新仓库"
        echo "  0. 退出"
        echo ""

        local selection
        while true; do
            read -p "选择 (0-$((repo_count+1))) [默认: 1]: " selection
            selection="${selection:-1}"

            if [[ "$selection" == "0" ]]; then
                log_warn "已退出"
                exit 0
            fi

            if [[ "$selection" == "$((repo_count+1))" ]]; then
                break
            fi

            if [[ "$selection" =~ ^[0-9]+$ ]] && \
               [[ "$selection" -ge 1 ]] && \
               [[ "$selection" -le "$repo_count" ]]; then
                selected_name="${repo_names[$((selection-1))]}"
                selected_location="${repo_locations[$((selection-1))]}"
                break
            fi

            echo "无效选择，请重试。"
        done
    fi

    # 3. 新建仓库流程
    if [[ -z "$selected_name" ]]; then
        echo ""
        log_substep "开始创建新 Docker 仓库配置:"
        
        # 3.1 输入仓库名称
        prompt_with_default "请输入新仓库名称" "proxy"
        local new_repo_name="$INPUT_VALUE"

        # 3.2 派生默认区域并输入
        local default_location="us-west1"
        if [[ -n "$zone" ]]; then
            default_location=$(_ar_zone_to_region "$zone")
        fi
        prompt_with_default "请输入新仓库区域" "$default_location"
        local new_repo_location="$INPUT_VALUE"

        # 3.3 检查是否已存在（避免静默重复创建或报错）
        if _ar_repo_exists "$project" "$new_repo_location" "$new_repo_name"; then
            log_success "检测到输入的仓库已存在，将直接使用: $new_repo_name (区域: $new_repo_location)"
            selected_name="$new_repo_name"
            selected_location="$new_repo_location"
        else
            log_substep "创建 Docker 仓库: $new_repo_name (位置: $new_repo_location)..."
            gcloud artifacts repositories create "$new_repo_name" \
                --project="$project" \
                --repository-format=docker \
                --location="$new_repo_location" \
                --description="Proxy subscription service image" \
                --quiet
            log_success "Artifact Registry 仓库已创建: $new_repo_name"
            selected_name="$new_repo_name"
            selected_location="$new_repo_location"
        fi
    else
        log_success "已选择现有仓库: $selected_name (区域: $selected_location)"
    fi

    # 4. 导出供后续步骤使用
    export AR_LOCATION="$selected_location"
    export AR_REPOSITORY="$selected_name"
    export AR_HOST="${selected_location}-docker.pkg.dev"
    export AR_IMAGE="${AR_HOST}/${project}/${selected_name}/subscription"
}


# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ -z "$PROJECT_ID" ]]; then
        read -p "请输入 Project ID: " PROJECT_ID
    fi
    if [[ -z "$VM_ZONE" ]]; then
        read -p "请输入 VM Zone (如 us-west1-b): " VM_ZONE
    fi
    setup_artifact_registry "$PROJECT_ID" "$VM_ZONE"
    echo "AR_LOCATION=$AR_LOCATION"
    echo "AR_REPOSITORY=$AR_REPOSITORY"
    echo "AR_IMAGE=$AR_IMAGE"
fi
