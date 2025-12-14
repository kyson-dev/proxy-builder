#!/bin/bash
# ==============================================================================
# 选择 GCP 项目
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
select_gcp_project() {
    log_step "Step 1: 选择 GCP 项目"
    echo ""
    
    require_gcloud
    
    local current_project
    current_project=$(gcp_get_current_project)
    
    log_substep "正在获取 GCP 项目列表..."
    
    local projects=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && projects+=("$line")
    done < <(gcp_list_projects)
    
    if [[ ${#projects[@]} -eq 0 ]]; then
        log_warn "未找到可用项目或无法列出项目"
        prompt_required "请输入 GCP Project ID"
        PROJECT_ID="$INPUT_VALUE"
    else
        echo ""
        echo "可用项目:"
        local i=1
        for project in "${projects[@]}"; do
            if [[ "$project" == "$current_project" ]]; then
                echo "  $i. $project (当前)"
            else
                echo "  $i. $project"
            fi
            ((i++))
        done
        echo "  0. 手动输入"
        echo ""
        
        while true; do
            read -p "选择项目 (0-${#projects[@]}) [默认: $current_project]: " selection
            
            # 空输入使用当前项目
            if [[ -z "$selection" ]] && [[ -n "$current_project" ]]; then
                PROJECT_ID="$current_project"
                break
            fi
            
            if [[ "$selection" == "0" ]]; then
                read -p "请输入 GCP Project ID: " PROJECT_ID
                break
            fi
            
            if [[ "$selection" =~ ^[0-9]+$ ]] && \
               [[ "$selection" -ge 1 ]] && \
               [[ "$selection" -le "${#projects[@]}" ]]; then
                PROJECT_ID="${projects[$((selection-1))]}"
                break
            fi
            
            echo "无效选择，请重试。"
        done
    fi
    
    log_success "使用项目: $PROJECT_ID"
    echo ""
    
    export PROJECT_ID
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    select_gcp_project
    echo "PROJECT_ID=$PROJECT_ID"
fi
