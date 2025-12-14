#!/bin/bash
set -e

# 加载环境变量
if [ -f .env ]; then
    set -a
    source .env
    set +a
else
    echo "❌ 未找到 .env 文件，请先创建"
    exit 1
fi

echo "🚀 开始部署简化代理服务..."
echo ""

# 检查必需的环境变量
if [ -z "$VLESS_UUID" ] || [ -z "$REALITY_PRIVATE_KEY" ] || [ -z "$REALITY_SHORT_ID" ] || [ -z "$H2_PASSWORD" ]; then
    echo "❌ 错误: 缺少必要的环境变量"
    echo "   需要: VLESS_UUID, REALITY_PRIVATE_KEY, REALITY_SHORT_ID, H2_PASSWORD"
    exit 1
fi

# 检查 Docker 权限
DOCKER_CMD="docker"
if ! docker info >/dev/null 2>&1; then
    if sudo docker info >/dev/null 2>&1; then
        echo "🔒 需要 sudo 权限来运行 Docker"
        DOCKER_CMD="sudo docker"
    else
        echo "❌ 无法运行 Docker (即使使用 sudo)。请检查 Docker 是否安装及权限配置。"
        exit 1
    fi
fi

# 检查并生成自签名证书
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
    
    # 检查 openssl 是否可用
    if ! command -v openssl &> /dev/null; then
        echo "   ❌ 错误: 未找到 openssl 命令"
        echo "   请先安装 openssl: apt install openssl 或 yum install openssl"
        exit 1
    fi
    
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

# 启动服务
echo ""
echo "🚀 启动服务..."

# 拉取最新镜像
echo "   ⬇️  拉取最新镜像..."
$DOCKER_CMD compose pull

# 启动服务
echo "   🔥 启动 Sing-box..."
$DOCKER_CMD compose up -d --remove-orphans

# 健康检查
echo ""
echo "⏳ 等待服务就绪..."
sleep 5

echo "📊 服务状态:"
$DOCKER_CMD compose ps

# 验证 Sing-box 是否运行
if $DOCKER_CMD compose ps sing-box | grep -q "Up"; then
    echo ""
    echo "✅ 部署成功！"
    echo ""
    echo "📋 代理服务信息:"
    echo "   VLESS Reality: <SERVER_IP>:8443"
    echo "   Hysteria2:     <SERVER_IP>:9443 (自签名证书)"
    echo ""
    echo "📝 查看日志: docker logs -f sing-box"
    echo ""
    echo "⚠️  注意: Hysteria2 使用自签名证书，客户端需要设置 insecure=true 或导入证书"
else
    echo ""
    echo "❌ Sing-box 启动失败，请检查日志:"
    echo "   docker logs sing-box"
    exit 1
fi
