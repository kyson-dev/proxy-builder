#!/bin/bash
# ==============================================================================
# 推送多环境用户 JSON 配置文件到 GitHub Secrets 执行子模块
# ==============================================================================

# 防止重复加载
[[ -n "${_ENV_PUSH_USERS_LOADED:-}" ]] && return 0
_ENV_PUSH_USERS_LOADED=1

# 推送用户配置列表 JSON
# 参数: <env_name> <project_root> [<repo>]
push_users_json() {
    local env_name="$1"
    local project_root="$2"
    local repo="$3"
    
    if [[ -z "$env_name" || -z "$project_root" ]]; then
        die "push_users_json 用法: push_users_json <env_name> <project_root> [<repo>]"
    fi
    
    # 查找特定环境的 JSON，若不存在则寻找 generic users.json
    local users_file="users.${env_name}.json"
    local users_file_path="${project_root}/${users_file}"
    
    if [[ ! -f "$users_file_path" ]]; then
        users_file="users.json"
        users_file_path="${project_root}/${users_file}"
    fi
    
    if [[ -f "$users_file_path" ]]; then
        log_step "发现用户列表文件: ${users_file}，准备推送到 GitHub Secrets"
        
        local users_json_content
        if ! command_exists jq; then
            log_warn "系统未安装 jq，将直接读取原始 JSON 文本进行上传"
            users_json_content=$(cat "$users_file_path")
        else
            users_json_content=$(jq -c . "$users_file_path")
        fi
        
        # 上传到 GitHub Secret USERS_JSON
        if github_set_secret "USERS_JSON" "$users_json_content" "$env_name" "$repo"; then
            ENV_UPLOADED_COUNT=$((ENV_UPLOADED_COUNT + 1))
        else
            ENV_FAILED_COUNT=$((ENV_FAILED_COUNT + 1))
        fi
    else
        log_substep "未检测到 users.${env_name}.json 或 users.json，跳过用户配置上传"
    fi
}
