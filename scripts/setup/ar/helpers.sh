#!/bin/bash
# ==============================================================================
# Artifact Registry 辅助功能函数库
# 职责: 提供交互式参数获取与用户选择的辅助函数，不包含任何物理创建逻辑
# ==============================================================================

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
# 交互式选择或配置 AR 仓库（回传值方式）
# 参数:
#   $1  project_id        GCP 项目 ID (必须)
#   $2  default_name      默认仓库名称 (可选，默认: proxy)
#   $3  default_location  默认区域 (可选，默认: us-west1)
#   $4  out_loc_var       用于接收所选区域的变量名 (必须)
#   $5  out_repo_var      用于接收所选仓库名称的变量名 (必须)
# ------------------------------------------------------------------------------
ar_select_or_configure_interactive() {
    local project="$1"
    local default_name="${2:-proxy}"
    local default_location="${3:-us-west1}"
    local out_loc_var="$4"
    local out_repo_var="$5"

    if [[ -z "$project" ]]; then
        die "ar_select_or_configure_interactive: PROJECT_ID 未设置"
    fi
    if [[ -z "$out_loc_var" ]] || [[ -z "$out_repo_var" ]]; then
        die "ar_select_or_configure_interactive: 必须指定回传变量名"
    fi

    log_step "设置 Artifact Registry"

    # 1. 获取现有 Docker 仓库列表
    log_substep "正在获取 Artifact Registry 仓库列表..."
    local repo_list
    repo_list=$(gcloud artifacts repositories list \
        --project="$project" \
        --filter="format=docker" \
        --format="value[no-transforms](name)" 2>/dev/null || echo "")

    local repo_names=()
    local repo_locations=()
    local repo_count=0

    if [[ -n "$repo_list" ]]; then
        while read -r name; do
            if [[ -n "$name" ]]; then
                local base_name
                base_name=$(basename "$name")
                
                local temp="${name#*/locations/}"
                local location="${temp%%/repositories/*}"
                
                repo_names+=("$base_name")
                repo_locations+=("$location")
                ((repo_count++))
            fi
        done <<< "$repo_list"
    fi

    local selected_name=""
    local selected_location=""

    # 2. 交互式选择或配置
    if [[ $repo_count -gt 0 ]]; then
        echo ""
        echo "现有 Docker 仓库实例:"
        local i
        for ((i=0; i<repo_count; i++)); do
            echo "  $((i+1)). ${repo_names[$i]} (区域: ${repo_locations[$i]})"
        done
        echo ""
        echo "  $((repo_count+1)). 🆕 配置新仓库"
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

    # 3. 新建仓库交互收集（不执行创建）
    if [[ -z "$selected_name" ]]; then
        echo ""
        log_substep "配置新 Docker 仓库参数:"
        
        prompt_with_default "请输入新仓库名称" "$default_name"
        local new_repo_name="$INPUT_VALUE"

        prompt_with_default "请输入新仓库区域" "$default_location"
        local new_repo_location="$INPUT_VALUE"

        selected_name="$new_repo_name"
        selected_location="$new_repo_location"
    else
        log_success "已选择现有仓库: $selected_name (区域: $selected_location)"
    fi

    # 4. 利用变量名传递回传结果
    eval "$out_loc_var=\"$selected_location\""
    eval "$out_repo_var=\"$selected_name\""
}
