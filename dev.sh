#!/bin/bash
# ==============================================================================
# 本地开发测试脚本
# 
# 用途：在本地快速启动 S-UI 进行测试
# 注意：不包含生产环境的 BBR、防火墙等配置
# ==============================================================================
set -e

echo "🚀 启动本地 S-UI 测试环境..."
echo ""

# 数据根目录（本地开发使用项目目录下的 data）
export DATA_ROOT="$(pwd)/data"
export S_UI_DATA_DIR="${DATA_ROOT}/s-ui"

# 检查 Docker
if ! command -v docker &>/dev/null; then
    echo "❌ 错误: 未安装 Docker"
    echo "请先安装 Docker Desktop: https://www.docker.com/products/docker-desktop"
    exit 1
fi

if ! docker info &>/dev/null 2>&1; then
    echo "❌ 错误: Docker 未运行"
    echo "请启动 Docker Desktop"
    exit 1
fi

# 创建数据目录
echo "📁 创建数据目录..."
mkdir -p "${S_UI_DATA_DIR}/db"
mkdir -p "${S_UI_DATA_DIR}/cert"

echo "   数据根目录: $DATA_ROOT"
echo "   S-UI 数据: $S_UI_DATA_DIR"

# 生成自签名证书（如果不存在）
if [ ! -f "${S_UI_DATA_DIR}/cert/cert.pem" ] || [ ! -f "${S_UI_DATA_DIR}/cert/key.pem" ]; then
    echo ""
    echo "🔐 生成自签名证书..."
    openssl req -x509 -nodes -newkey rsa:2048 \
        -keyout "${S_UI_DATA_DIR}/cert/key.pem" \
        -out "${S_UI_DATA_DIR}/cert/cert.pem" \
        -subj "/CN=localhost" \
        -days 365 >/dev/null 2>&1
    chmod 644 "${S_UI_DATA_DIR}/cert/cert.pem"
    chmod 600 "${S_UI_DATA_DIR}/cert/key.pem"
    echo "✅ 证书已生成"
fi

# 启动服务
echo ""
echo "🐳 启动 Docker Compose..."
docker compose up -d

# 等待服务就绪
echo "⏳ 等待服务启动..."
sleep 5

# 检查服务状态
if docker compose ps s-ui 2>/dev/null | grep -q "Up"; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ S-UI 启动成功！"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "📋 访问信息:"
    echo "   Web 面板: http://localhost:2095/app/"
    echo "   订阅服务: http://localhost:2096/sub/"
    echo ""
    echo "🔐 默认登录:"
    echo "   用户名: admin"
    echo "   密码: admin"
    echo ""
    echo "⚠️  安全提示: 首次登录后请立即修改默认密码！"
    echo ""
    echo "📂 数据目录: $S_UI_DATA_DIR"
    echo ""
    echo "📝 常用命令:"
    echo "   查看日志: docker compose logs -f s-ui"
    echo "   停止服务: docker compose down"
    echo "   重启服务: docker compose restart"
    echo ""
else
    echo ""
    echo "❌ 服务启动失败"
    echo ""
    echo "查看日志:"
    docker compose logs s-ui --tail 20
    exit 1
fi

