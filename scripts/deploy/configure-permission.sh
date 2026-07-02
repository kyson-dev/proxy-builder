#!/bin/bash
# ==============================================================================
# 配置与校验全局工作目录权限
# ==============================================================================

# 如果直接运行，加载依赖
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_SELF_DIR}/../lib/common.sh"
    source "${_SELF_DIR}/../lib/paths.sh"
fi

# ------------------------------------------------------------------------------
# 检测目录及权限是否就绪
# ------------------------------------------------------------------------------
is_permission_ready() {
    local root_dir="${PROXY_ROOT}"
    
    if [[ ! -d "$root_dir" ]]; then
        return 1
    fi
    
    local current_owner current_group
    current_owner=$(stat -c %U "$root_dir" 2>/dev/null || echo "")
    current_group=$(stat -c %G "$root_dir" 2>/dev/null || echo "")
    
    if [[ "$current_owner" != "$USER" ]]; then
        return 1
    fi
    if [[ "$current_group" != "docker" ]]; then
        return 1
    fi
    if [[ ! -g "$root_dir" ]]; then
        return 1
    fi
    
    return 0
}

# ------------------------------------------------------------------------------
# 设置根目录所有权与权限自举
# ------------------------------------------------------------------------------
configure_permission() {
    log_step "配置全局工作根目录所有权与权限"
    
    local root_dir="${PROXY_ROOT}"
    local target_user="${SUDO_USER:-$USER}"
    
    log_substep "确保工作根目录存在: ${root_dir}"
    mkdir -p "${root_dir}"
    
    # 确保执行部署的主机用户被加入到 docker 用户组
    if [[ -n "$target_user" && "$target_user" != "root" ]]; then
        log_substep "确保用户 ${target_user} 已加入 docker 组..."
        groupadd -f docker || true
        usermod -aG docker "$target_user" || true
    fi
    
    log_substep "设置根目录所有权为 ${target_user}:docker..."
    chown -R "${target_user}:docker" "${root_dir}"
    
    log_substep "设置组写权限 (775)..."
    chmod 775 "${root_dir}"
    
    log_substep "设置 SGID 保证后续新建文件自动继承 docker 组..."
    chmod g+s "${root_dir}"
    
    log_success "工作根目录授权完成"
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if is_permission_ready; then
        log_success "权限环境完全就绪"
    else
        log_warn "检测到权限配置不全，执行自动配置中..."
        configure_permission
    fi
fi
