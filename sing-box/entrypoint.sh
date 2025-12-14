#!/bin/sh
set -e

# Check if config template exists
if [ ! -f /etc/sing-box/config.json.template ]; then
  echo "Error: config.json.template not found"
  exit 1
fi

# Check required environment variables
if [ -z "$VLESS_UUID" ] || [ -z "$REALITY_PRIVATE_KEY" ] || [ -z "$REALITY_SHORT_ID" ] || [ -z "$H2_PASSWORD" ]; then
  echo "Error: One or more required environment variables are missing."
  echo "Required: VLESS_UUID, REALITY_PRIVATE_KEY, REALITY_SHORT_ID, H2_PASSWORD"
  exit 1
fi

echo "Generating configuration from template..."

# Copy template
cp /etc/sing-box/config.json.template /etc/sing-box/config.json

# Replace variables using sed
sed -i "s|\${VLESS_UUID}|$VLESS_UUID|g" /etc/sing-box/config.json
sed -i "s|\${REALITY_PRIVATE_KEY}|$REALITY_PRIVATE_KEY|g" /etc/sing-box/config.json
sed -i "s|\${REALITY_SHORT_ID}|$REALITY_SHORT_ID|g" /etc/sing-box/config.json
sed -i "s|\${H2_PASSWORD}|$H2_PASSWORD|g" /etc/sing-box/config.json

echo "Configuration generated successfully."

# Validate configuration
echo "Validating configuration..."
if ! sing-box check -c /etc/sing-box/config.json; then
  echo "Error: Invalid configuration generated."
  echo "Dumping generated configuration for debugging:"
  cat /etc/sing-box/config.json
  exit 1
fi

# Start sing-box
exec sing-box run -c /etc/sing-box/config.json
