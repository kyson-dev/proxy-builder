#!/bin/sh
set -e

# 检查配置文件模板是否存在
if [ ! -f /etc/sing-box/config.json.template ]; then
  echo "Error: config.json.template not found"
  exit 1
fi

echo "Generating configuration from template..."

# 复制模板
cp /etc/sing-box/config.json.template /etc/sing-box/config.json

# 使用 sed 逐个替换变量
# 使用 | 作为分隔符，避免与路径中的 / 冲突
sed -i "s|\${DOMAIN}|$DOMAIN|g" /etc/sing-box/config.json
sed -i "s|\${VLESS_UUID}|$VLESS_UUID|g" /etc/sing-box/config.json
sed -i "s|\${REALITY_PRIVATE_KEY}|$REALITY_PRIVATE_KEY|g" /etc/sing-box/config.json
sed -i "s|\${REALITY_SHORT_ID}|$REALITY_SHORT_ID|g" /etc/sing-box/config.json
sed -i "s|\${PROXY_PASSWORD}|$PROXY_PASSWORD|g" /etc/sing-box/config.json

echo "Configuration generated successfully."

# 显示生成的配置（仅用于调试，生产环境应注释掉）
# cat /etc/sing-box/config.json

# 启动 sing-box
exec sing-box run -c /etc/sing-box/config.json
# echo "DEBUG MODE: Sleeping..."
# sleep infinity
