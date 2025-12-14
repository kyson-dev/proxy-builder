#!/bin/bash
set -e

echo "🚀 开始部署简化代理服务..."
echo ""

# =============================================================================
# 0. 启用 BBR 拥塞控制算法
# =============================================================================
enable_bbr() {
    echo "🚀 检查 BBR 拥塞控制..."
    
    # 检查当前拥塞控制算法
    CURRENT_CC=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
    
    if [ "$CURRENT_CC" = "bbr" ]; then
        echo "   ✅ BBR 已启用"
        return 0
    fi
    
    echo "   当前拥塞控制: $CURRENT_CC"
    echo "   📝 正在启用 BBR..."
    
    # 检查内核是否支持 BBR (Linux 4.9+)
    if ! grep -q bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
        # 尝试加载 BBR 模块
        sudo modprobe tcp_bbr 2>/dev/null || true
    fi
    
    # 再次检查是否可用
    if ! grep -q bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
        echo "   ⚠️  内核不支持 BBR (需要 Linux 4.9+)"
        echo "   当前内核: $(uname -r)"
        return 0
    fi
    
    # 配置 sysctl 参数
    sudo tee /etc/sysctl.d/99-bbr.conf > /dev/null << 'EOF'
# BBR congestion control
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# 优化网络性能
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_fastopen = 3
EOF
    
    # 应用配置
    sudo sysctl -p /etc/sysctl.d/99-bbr.conf > /dev/null 2>&1 || sudo sysctl --system > /dev/null 2>&1
    
    # 验证
    NEW_CC=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
    if [ "$NEW_CC" = "bbr" ]; then
        echo "   ✅ BBR 启用成功"
    else
        echo "   ⚠️  BBR 启用失败，使用默认拥塞控制: $NEW_CC"
    fi
}

# 启用 BBR
enable_bbr
echo ""

# =============================================================================
# 1. 检查并安装必要的工具
# =============================================================================
install_docker() {
    echo "📦 安装 Docker..."
    
    # 检测操作系统
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        echo "❌ 无法检测操作系统"
        exit 1
    fi
    
    case $OS in
        ubuntu|debian)
            echo "   检测到 $OS，使用 apt 安装..."
            sudo apt-get update -qq
            sudo apt-get install -y -qq ca-certificates curl gnupg
            
            # 添加 Docker 官方 GPG 密钥
            sudo install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/$OS/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null || true
            sudo chmod a+r /etc/apt/keyrings/docker.gpg
            
            # 添加 Docker 仓库
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
                sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            # 安装 Docker
            sudo apt-get update -qq
            sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        centos|rhel|fedora|rocky|almalinux)
            echo "   检测到 $OS，使用 yum/dnf 安装..."
            sudo yum install -y -q yum-utils || sudo dnf install -y -q dnf-plugins-core
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo 2>/dev/null || \
                sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo 2>/dev/null
            sudo yum install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || \
                sudo dnf install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        *)
            echo "   未知操作系统，尝试使用官方安装脚本..."
            curl -fsSL https://get.docker.com | sudo sh
            ;;
    esac
    
    # 启动 Docker 服务
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # 将当前用户添加到 docker 组（下次登录生效）
    sudo usermod -aG docker $USER 2>/dev/null || true
    
    echo "   ✅ Docker 安装完成"
}

install_openssl() {
    echo "📦 安装 OpenSSL..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    fi
    
    case $OS in
        ubuntu|debian)
            sudo apt-get update -qq
            sudo apt-get install -y -qq openssl
            ;;
        centos|rhel|fedora|rocky|almalinux)
            sudo yum install -y -q openssl || sudo dnf install -y -q openssl
            ;;
        *)
            echo "❌ 无法自动安装 openssl，请手动安装"
            exit 1
            ;;
    esac
    
    echo "   ✅ OpenSSL 安装完成"
}

echo "🔍 检查必要的工具..."

# 检查 Docker
if ! command -v docker &> /dev/null; then
    echo "   ⚠️  Docker 未安装"
    install_docker
else
    echo "   ✅ Docker 已安装: $(docker --version | head -1)"
fi

# 检查 Docker Compose (V2 plugin)
if ! docker compose version &> /dev/null 2>&1; then
    if ! sudo docker compose version &> /dev/null 2>&1; then
        echo "   ⚠️  Docker Compose 未安装，重新安装 Docker..."
        install_docker
    fi
fi
echo "   ✅ Docker Compose 已安装"

# 检查 OpenSSL
if ! command -v openssl &> /dev/null; then
    echo "   ⚠️  OpenSSL 未安装"
    install_openssl
else
    echo "   ✅ OpenSSL 已安装"
fi

echo ""

# =============================================================================
# 2. 解析变量配置文件 (vars.json)
# =============================================================================
if [ ! -f vars.json ]; then
    echo "❌ 未找到 vars.json 文件"
    echo "   请确保部署时已创建此文件"
    exit 1
fi

echo "📋 解析配置变量..."

# 检查 jq 是否可用
if ! command -v jq &> /dev/null; then
    echo "   ⚠️  jq 未安装，正在安装..."
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case $ID in
            ubuntu|debian)
                sudo apt-get update -qq && sudo apt-get install -y -qq jq
                ;;
            centos|rhel|fedora|rocky|almalinux)
                sudo yum install -y -q jq || sudo dnf install -y -q jq
                ;;
        esac
    fi
fi

# 从 JSON 提取变量并导出
export VLESS_PORT=$(jq -r '.ports.vless // 443' vars.json)
export H2_PORT=$(jq -r '.ports.hysteria2 // 443' vars.json)
export VLESS_USERS=$(jq -c '.vless_users' vars.json)
export H2_USERS=$(jq -c '.h2_users' vars.json)
export REALITY_PRIVATE_KEY=$(jq -r '.reality.private_key' vars.json)
export REALITY_PUBLIC_KEY=$(jq -r '.reality.public_key' vars.json)
export REALITY_SHORT_ID=$(jq -r '.reality.short_id' vars.json)

# 验证必需变量
if [ -z "$VLESS_USERS" ] || [ "$VLESS_USERS" = "null" ] || \
   [ -z "$H2_USERS" ] || [ "$H2_USERS" = "null" ] || \
   [ -z "$REALITY_PRIVATE_KEY" ] || [ "$REALITY_PRIVATE_KEY" = "null" ]; then
    echo "❌ 配置文件中缺少必要的变量"
    exit 1
fi

echo "   ✅ 配置解析完成 (VLESS:$VLESS_PORT, Hysteria2:$H2_PORT)"
echo ""

# =============================================================================
# 3. 检查 Docker 权限
# =============================================================================
DOCKER_CMD="docker"
if ! docker info >/dev/null 2>&1; then
    if sudo docker info >/dev/null 2>&1; then
        echo "🔒 需要 sudo 权限来运行 Docker"
        DOCKER_CMD="sudo docker"
    else
        echo "❌ 无法运行 Docker。请检查 Docker 服务是否启动。"
        echo "   尝试: sudo systemctl start docker"
        exit 1
    fi
fi

# =============================================================================
# 4. 检查并生成自签名证书
# =============================================================================
echo "🔐 检查 Hysteria2 自签名证书..."
CERT_DIR="./sing-box/certs"
mkdir -p "$CERT_DIR"

NEED_GENERATE=false

# 检查证书文件是否存在
if [ ! -f "$CERT_DIR/cert.pem" ] || [ ! -f "$CERT_DIR/key.pem" ]; then
    echo "   ⚠️  证书文件不存在"
    NEED_GENERATE=true
else
    # 检查证书是否有效
    if ! openssl x509 -in "$CERT_DIR/cert.pem" -noout -checkend 86400 >/dev/null 2>&1; then
        echo "   ⚠️  证书已过期或无效"
        NEED_GENERATE=true
    else
        echo "   ✅ 证书已存在且有效"
        # 显示证书信息
        CERT_CN=$(openssl x509 -in "$CERT_DIR/cert.pem" -noout -subject 2>/dev/null | sed -n 's/.*CN=\([^,]*\).*/\1/p')
        CERT_EXPIRE=$(openssl x509 -in "$CERT_DIR/cert.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
        echo "   📋 CN: $CERT_CN"
        echo "   📅 过期时间: $CERT_EXPIRE"
    fi
fi

if [ "$NEED_GENERATE" = true ]; then
    echo "   📝 生成新的自签名证书..."
    
    # 使用 OpenSSL 生成自签名证书 (使用 RSA 以确保兼容性)
    openssl req -x509 -nodes -newkey rsa:2048 \
        -keyout "$CERT_DIR/key.pem" \
        -out "$CERT_DIR/cert.pem" \
        -subj "/CN=bing.com" \
        -days 36500 >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo "   ✅ 自签名证书生成成功"
        echo "   📋 CN: bing.com"
        echo "   📅 有效期: 100 年"
        # 设置正确的权限
        chmod 644 "$CERT_DIR/cert.pem"
        chmod 600 "$CERT_DIR/key.pem"
    else
        echo "   ❌ 证书生成失败，尝试使用 EC 密钥..."
        # 备用方案：分两步生成 EC 证书
        openssl ecparam -name prime256v1 -genkey -noout -out "$CERT_DIR/key.pem" 2>/dev/null && \
        openssl req -new -x509 -key "$CERT_DIR/key.pem" \
            -out "$CERT_DIR/cert.pem" \
            -subj "/CN=bing.com" \
            -days 36500 >/dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            echo "   ✅ 自签名证书生成成功 (EC 密钥)"
            chmod 644 "$CERT_DIR/cert.pem"
            chmod 600 "$CERT_DIR/key.pem"
        else
            echo "   ❌ 证书生成失败"
            echo "   请检查 openssl 安装和配置"
            exit 1
        fi
    fi
fi

# =============================================================================
# 5. 启动服务
# =============================================================================
echo ""
echo "🚀 启动服务..."

# 清理旧的 .env 文件（避免 docker compose 误读）
if [ -f .env ]; then
    echo "   🧹 清理旧的 .env 文件..."
    rm -f .env
fi

# 拉取最新镜像
echo "   ⬇️  拉取最新镜像..."
$DOCKER_CMD compose pull

# 启动服务
echo "   🔥 启动 Sing-box..."
$DOCKER_CMD compose up -d --remove-orphans

# =============================================================================
# 6. 健康检查
# =============================================================================
echo ""
echo "⏳ 等待服务就绪..."
sleep 5

echo "📊 服务状态:"
$DOCKER_CMD compose ps

# 获取服务器 IP
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ip.sb 2>/dev/null || echo "<SERVER_IP>")

# 验证 Sing-box 是否运行
if $DOCKER_CMD compose ps sing-box | grep -q "Up"; then
    echo ""
    echo "✅ 部署成功！"
    echo ""
    echo "📋 代理服务信息:"
    echo "   VLESS Reality: $SERVER_IP:$VLESS_PORT"
    echo "   Hysteria2:     $SERVER_IP:$H2_PORT (自签名证书)"
    echo ""
    echo "📝 查看日志: docker logs -f sing-box"
    echo ""
    echo "⚠️  注意: Hysteria2 使用自签名证书，客户端需要设置 insecure=true"
else
    echo ""
    echo "❌ Sing-box 启动失败，请检查日志:"
    echo "   docker logs sing-box"
    exit 1
fi
