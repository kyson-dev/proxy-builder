#!/bin/bash
# ==============================================================================
# 安装 Docker
# 注意: 此脚本应被主脚本 source，依赖库由主脚本加载
# ==============================================================================

# 如果直接运行，加载依赖
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_SELF_DIR}/../lib/common.sh"
    source "${_SELF_DIR}/../lib/os.sh"
    source "${_SELF_DIR}/../lib/docker.sh"
fi

# ------------------------------------------------------------------------------
# 安装 Docker
# ------------------------------------------------------------------------------
install_docker() {
    log_substep "安装 Docker..."
    
    detect_os
    
    case $OS_ID in
        ubuntu|debian)
            log_substep "检测到 $OS_ID，使用 apt 安装..."
            sudo apt-get update -qq
            sudo apt-get install -y -qq ca-certificates curl gnupg
            
            # 添加 Docker 官方 GPG 密钥
            sudo install -m 0755 -d /etc/apt/keyrings
            curl -fsSL "https://download.docker.com/linux/$OS_ID/gpg" | \
                sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null || true
            sudo chmod a+r /etc/apt/keyrings/docker.gpg
            
            # 添加 Docker 仓库
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS_ID $OS_CODENAME stable" | \
                sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            # 安装 Docker
            sudo apt-get update -qq
            sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
            
        centos|rhel|fedora|rocky|almalinux)
            log_substep "检测到 $OS_ID，使用 yum/dnf 安装..."
            sudo yum install -y -q yum-utils 2>/dev/null || \
                sudo dnf install -y -q dnf-plugins-core 2>/dev/null
            
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo 2>/dev/null || \
                sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo 2>/dev/null
            
            sudo yum install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || \
                sudo dnf install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null
            ;;
            
        *)
            log_substep "未知操作系统，尝试使用官方安装脚本..."
            curl -fsSL https://get.docker.com | sudo sh
            ;;
    esac
    
    # 启动 Docker 服务
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # 将当前用户添加到 docker 组
    sudo usermod -aG docker "$USER" 2>/dev/null || true
    
    log_success "Docker 安装完成"
}

# ------------------------------------------------------------------------------
# 检查 Docker
# ------------------------------------------------------------------------------
check_docker() {
    log_step "检查 Docker"
    
    if ! command_exists docker; then
        log_warn "Docker 未安装"
        install_docker
    else
        log_success "Docker 已安装: $(docker --version | head -1)"
    fi
    
    # 检查 Docker Compose (V2 plugin)
    if ! docker compose version &>/dev/null && ! sudo docker compose version &>/dev/null; then
        log_warn "Docker Compose 未安装，重新安装 Docker..."
        install_docker
    else
        log_success "Docker Compose 已安装"
    fi
}



# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_docker
    DOCKER_CMD=$(get_docker_cmd)
    echo "DOCKER_CMD=$DOCKER_CMD"
fi
