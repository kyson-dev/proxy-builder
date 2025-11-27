#!/bin/bash

# 域名替换脚本
# 用于快速更换项目中的所有域名配置

set -e

echo "🔄 域名替换工具"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 当前域名
CURRENT_DOMAIN="kyson.site"

# 提示输入新域名
read -p "请输入新域名（如 example.com）: " NEW_DOMAIN

if [ -z "$NEW_DOMAIN" ]; then
    echo "❌ 域名不能为空"
    exit 1
fi

echo ""
echo "📋 将要执行的操作："
echo "   旧域名: $CURRENT_DOMAIN"
echo "   新域名: $NEW_DOMAIN"
echo ""
echo "📁 将修改以下文件："
echo "   - nginx/nginx.conf"
echo "   - sing-box/config.json"
echo "   - deploy.sh"
echo "   - README.md"
echo "   - 其他文档文件"
echo ""

read -p "确认继续? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ 已取消"
    exit 1
fi

echo ""
echo "🔧 开始替换..."

# 替换所有文件中的域名
find . -type f \( -name "*.conf" -o -name "*.json" -o -name "*.sh" -o -name "*.md" -o -name "*.html" \) \
  -not -path "./.git/*" \
  -not -path "./change-domain.sh" \
  -exec sed -i '' "s/$CURRENT_DOMAIN/$NEW_DOMAIN/g" {} +

echo "✅ 域名替换完成！"
echo ""
echo "📝 下一步操作："
echo "   1. 检查配置文件是否正确："
echo "      - cat nginx/nginx.conf"
echo "      - cat sing-box/config.json"
echo "      - cat deploy.sh"
echo ""
echo "   2. 配置新域名的 DNS A 记录指向服务器 IP"
echo ""
echo "   3. 删除旧证书（如果存在）："
echo "      rm -rf certs/live/$CURRENT_DOMAIN"
echo ""
echo "   4. 重新部署："
echo "      ./deploy.sh"
echo ""
