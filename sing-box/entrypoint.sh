#!/bin/sh
set -e

# 检查配置文件模板是否存在
if [ ! -f /etc/sing-box/config.json.template ]; then
  echo "Error: config.json.template not found"
  exit 1
fi

# Check required environment variables
if [ -z "$DOMAIN" ] || [ -z "$VLESS_UUID" ] || [ -z "$REALITY_PRIVATE_KEY" ] || [ -z "$REALITY_SHORT_ID" ] || [ -z "$H2_PASSWORD" ] || [ -z "$TUIC_UUID" ] || [ -z "$TUIC_PASSWORD" ] ; then
  echo "Error: One or more required environment variables are missing."
  echo "Required: DOMAIN, VLESS_UUID, REALITY_PRIVATE_KEY, REALITY_SHORT_ID, H2_PASSWORD, TUIC_UUID, TUIC_PASSWORD"
  exit 1
fi

echo "Generating configuration from template..."

# 复制模板
cp /etc/sing-box/config.json.template /etc/sing-box/config.json

# 使用 sed 逐个替换变量
# 使用 | 作为分隔符，避免与路径中的 / 冲突
sed -i "s|\${DOMAIN}|$DOMAIN|g" /etc/sing-box/config.json
sed -i "s|\${VLESS_UUID}|$VLESS_UUID|g" /etc/sing-box/config.json
sed -i "s|\${REALITY_PRIVATE_KEY}|$REALITY_PRIVATE_KEY|g" /etc/sing-box/config.json`
sed -i "s|\${REALITY_SHORT_ID}|$REALITY_SHORT_ID|g" /etc/sing-box/config.json
sed -i "s|\${H2_PASSWORD}|$H2_PASSWORD|g" /etc/sing-box/config.json
sed -i "s|\${TUIC_UUID}|$TUIC_UUID|g" /etc/sing-box/config.json
sed -i "s|\${TUIC_PASSWORD}|$TUIC_PASSWORD|g" /etc/sing-box/config.json

echo "Configuration generated successfully."

# Validate configuration
echo "Validating configuration..."
if ! sing-box check -c /etc/sing-box/config.json; then
  echo "Error: Invalid configuration generated."
  echo "Dumping generated configuration for debugging:"
  cat /etc/sing-box/config.json
  exit 1
fi

# 启动 sing-box
exec sing-box run -c /etc/sing-box/config.json
# echo "DEBUG MODE: Sleeping..."
# sleep infinity
