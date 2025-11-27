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

# 启动 Nginx
echo ""
echo "1️⃣  启动 Nginx..."
docker compose up -d nginx

# 等待 Nginx 启动并检查健康状态
echo "   等待 Nginx 启动..."
for i in {1..10}; do
    if docker compose ps nginx | grep -q "Up"; then
        echo "   ✅ Nginx 已启动"
        break
    fi
    if [ $i -eq 10 ]; then
        echo "   ❌ Nginx 启动超时"
        exit 1
    fi
    sleep 1
done

# 申请证书
echo ""
echo "2️⃣  申请 SSL 证书..."
if [ ! -d "certs/live/$DOMAIN" ]; then
    # 使用 docker compose run 会忽略 depends_on，但我们已经确保 nginx 在运行
    docker compose run --rm certbot certbot certonly \
      --webroot -w /var/www/html \
      -d $DOMAIN \
      --agree-tos \
      --email $EMAIL \
      --non-interactive
    
    if [ $? -eq 0 ]; then
        echo "✅ 证书申请成功"
    else
        echo "❌ 证书申请失败，请检查日志"
        exit 1
    fi
else
    echo "✅ 证书已存在，跳过申请"
fi

# 启动所有服务
echo ""
echo "3️⃣  启动所有服务..."
docker compose up -d

# 等待服务启动
echo ""
echo "⏳ 等待服务启动..."
sleep 5

# 显示状态
echo ""
echo "📊 服务状态:"
docker compose ps

echo ""
echo "✅ 部署完成！"
echo ""
echo "📝 查看日志: docker compose logs -f"
echo "📱 客户端配置信息请查看 README.md"
