#!/bin/bash
# ==============================================================================
# 推送多环境配置文件变量到 GitHub Secrets 执行子模块
# ==============================================================================

# 防止重复加载
[[ -n "${_ENV_PUSH_SECRETS_LOADED:-}" ]] && return 0
_ENV_PUSH_SECRETS_LOADED=1

# 推送环境配置 Secret
# 参数: <env_name> <env_file_path> [<repo>]
push_env_secrets() {
    local env_name="$1"
    local env_file_path="$2"
    local repo="$3"
    
    if [[ -z "$env_name" || -z "$env_file_path" ]]; then
        die "push_env_secrets 用法: push_env_secrets <env_name> <env_file_path> [<repo>]"
    fi
    
    if [[ ! -f "$env_file_path" ]]; then
        die "配置文件不存在: $env_file_path"
    fi
    
    log_step "正在推送配置文件: $(basename "$env_file_path")"
    
    local local_uploaded=0
    local local_skipped=0
    local local_failed=0
    
    # 读取 .env 文件并逐个上传
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        # 跳过空行和注释
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
        
        # 去除前后空格
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        
        # 跳过空值
        if [[ -z "$value" ]]; then
            log_warn "跳过空值: $key"
            ((local_skipped++))
            continue
        fi
        
        # 调用公共库上传
        if github_set_secret "$key" "$value" "$env_name" "$repo"; then
            ((local_uploaded++))
        else
            ((local_failed++))
        fi
    done < "$env_file_path"
    
    # 导出统计计数供主脚本汇总
    ENV_UPLOADED_COUNT=$((ENV_UPLOADED_COUNT + local_uploaded))
    ENV_SKIPPED_COUNT=$((ENV_SKIPPED_COUNT + local_skipped))
    ENV_FAILED_COUNT=$((ENV_FAILED_COUNT + local_failed))
}
