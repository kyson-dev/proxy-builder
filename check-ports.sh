#!/bin/bash

echo "🔍 检查 Sing-box 端口监听状态..."
echo ""

echo "📡 监听端口："
netstat -tuln | grep -E ':(8443|9443|5443)' || ss -tuln | grep -E ':(8443|9443|5443)'

echo ""
echo "🔥 防火墙状态："
if command -v ufw &> /dev/null; then
    sudo ufw status | grep -E '(8443|9443|5443)'
elif command -v firewall-cmd &> /dev/null; then
    sudo firewall-cmd --list-ports
else
    echo "未检测到 ufw 或 firewalld"
fi

echo ""
echo "📊 Sing-box 进程："
ps aux | grep sing-box | grep -v grep

echo ""
echo "🌐 公网 IP："
curl -s ifconfig.me
echo ""

echo ""
echo "⚠️  请确保云服务商的安全组已开放以下端口："
echo "   - TCP/UDP 8443 (VLESS Reality)"
echo "   - UDP 9443 (Hysteria2)"
echo "   - UDP 5443 (TUIC)"
