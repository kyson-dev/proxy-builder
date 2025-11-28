#!/bin/bash
set -e

# 加载环境变量
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
else
    echo "❌ 未找到 .env 文件，请先创建"
    exit 1
fi

echo "🚀 开始部署代理服务..."
echo "   域名: $DOMAIN"
echo ""

# 检查 DNS
echo "📡 检查 DNS 配置..."
if ! host $DOMAIN > /dev/null 2>&1; then
    echo "⚠️  警告: $DOMAIN DNS 解析失败"
    echo "   请确保域名 A 记录已指向服务器 IP"
    read -p "   是否继续? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# 注册清理函数：确保脚本退出或中断时恢复 Nginx 配置
cleanup() {
    if [ -f nginx/nginx.conf.bak ]; then
        echo ""
        echo "🧹 检测到脚本中断，正在恢复 Nginx 原始配置..."
        mv nginx/nginx.conf.bak nginx/nginx.conf
    fi
}
trap cleanup EXIT INT TERM

# -----------------------------------------------------------------------------
# 1. 证书检查与申请模块
# -----------------------------------------------------------------------------
echo ""
echo "🔍 检查 SSL 证书状态..."

# 使用容器内部检查证书，避免宿主机权限问题导致误判
if ! docker compose run --rm --entrypoint "test" certbot -f /etc/letsencrypt/live/$DOMAIN/fullchain.pem; then
    echo "   ⚠️  未检测到证书，准备申请..."
    echo "   1️⃣  启动临时 Nginx (HTTP 模式)..."
    
    # 备份现有配置
    if [ -f nginx/nginx.conf ]; then
        cp nginx/nginx.conf nginx/nginx.conf.bak
    fi
    
    # 创建一个仅 HTTP 的临时配置
    cat > nginx/nginx.conf <<EOF
events {
    worker_connections 1024;
}
http {
    server {
        listen 80;
        server_name $DOMAIN;
        location /.well-known/acme-challenge/ {
            root /var/www/html;
        }
        location / {
            return 200 'Nginx is running for Certbot validation';
            add_header Content-Type text/plain;
        }
    }
}
EOF

    # 启动 Nginx
    docker compose up -d nginx

    # 等待 Nginx 启动
    echo "      等待 Nginx 启动..."
    for i in {1..10}; do
        if docker compose ps nginx | grep -q "Up"; then
            echo "      ✅ Nginx 已启动"
            break
        fi
        if [ $i -eq 10 ]; then
            echo "      ❌ Nginx 启动超时"
            exit 1
        fi
        sleep 1
    done

    echo "   2️⃣  申请 SSL 证书..."
    echo "      ⚠️  注意：如果卡住，请检查防火墙是否开放 80 端口"
    
    # 申请证书
    # 注意：必须使用 --entrypoint 覆盖 docker-compose.yml 中定义的自动续期(死循环)脚本
    docker compose run --rm --entrypoint "certbot" certbot certonly \
      --webroot -w /var/www/html \
      -d $DOMAIN \
      --agree-tos \
      --email $EMAIL \
      --non-interactive
    
    CERT_EXIT_CODE=$?
    
    # 无论成功失败，都恢复原始配置
    if [ -f nginx/nginx.conf.bak ]; then
        echo "   3️⃣  恢复原始 Nginx 配置..."
        mv nginx/nginx.conf.bak nginx/nginx.conf
    fi

    if [ $CERT_EXIT_CODE -eq 0 ]; then
        echo "      ✅ 证书申请成功"
        # 停止临时 Nginx，让后续的主流程统一启动
        docker compose stop nginx
    else
        echo "      ❌ 证书申请失败"
        exit 1
    fi
else
    echo "   ✅ 证书已存在，跳过申请"
fi

# -----------------------------------------------------------------------------
# 2. 服务启动/更新模块
# -----------------------------------------------------------------------------
echo ""
echo "🚀 启动/更新服务..."

# 拉取最新镜像
echo "   ⬇️  拉取最新镜像..."
docker compose pull

# 启动所有服务
echo "   🔥 启动服务 (Zero Downtime)..."
docker compose up -d --remove-orphans

# -----------------------------------------------------------------------------
# 3. 健康检查模块
# -----------------------------------------------------------------------------
echo ""
echo "⏳ 等待服务就绪..."
sleep 5

echo "📊 服务状态:"
docker compose ps

# 简单验证 Sing-box 是否运行
if docker compose ps sing-box | grep -q "Up"; then
    echo ""
    echo "✅ 部署成功！"
    echo "📝 查看日志: docker compose logs -f"
else
    echo ""
    echo "❌ 部署可能存在问题，Sing-box 未正常运行"
    docker compose logs sing-box
    exit 1
fi
