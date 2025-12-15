#!/bin/sh
set -e

if [ ! -f /etc/sing-box/config.json.template ]; then
  echo "Error: config.json.template not found"
  exit 1
fi

# Check required environment variables
if [ -z "$VLESS_USERS" ] || [ -z "$REALITY_PRIVATE_KEY" ] || [ -z "$REALITY_SHORT_ID" ] || [ -z "$H2_USERS" ]; then
  echo "Error: Missing required environment variables"
  echo "Required: VLESS_USERS, H2_USERS, REALITY_PRIVATE_KEY, REALITY_SHORT_ID"
  exit 1
fi

# Set default values if not provided
VLESS_PORT=${VLESS_PORT:-443}
H2_PORT=${H2_PORT:-443}
REALITY_SERVER_NAME=${REALITY_SERVER_NAME:-www.microsoft.com}

echo "Generating configuration from template..."

# Copy template
cp /etc/sing-box/config.json.template /etc/sing-box/config.json

# Replace variables
# Compress JSON to single line for safety
VLESS_USERS_ESCAPED=$(echo "$VLESS_USERS" | tr '\n' ' ' | sed 's/  */ /g')
H2_USERS_ESCAPED=$(echo "$H2_USERS" | tr '\n' ' ' | sed 's/  */ /g')

sed -i "s|\${VLESS_PORT}|$VLESS_PORT|g" /etc/sing-box/config.json
sed -i "s|\${H2_PORT}|$H2_PORT|g" /etc/sing-box/config.json
sed -i "s|\${VLESS_USERS}|$VLESS_USERS_ESCAPED|g" /etc/sing-box/config.json
sed -i "s|\${H2_USERS}|$H2_USERS_ESCAPED|g" /etc/sing-box/config.json
sed -i "s|\${REALITY_PRIVATE_KEY}|$REALITY_PRIVATE_KEY|g" /etc/sing-box/config.json
sed -i "s|\${REALITY_SHORT_ID}|$REALITY_SHORT_ID|g" /etc/sing-box/config.json
sed -i "s|\${REALITY_SERVER_NAME}|$REALITY_SERVER_NAME|g" /etc/sing-box/config.json

echo "Configuration generated successfully."
echo "  REALITY_SERVER_NAME: $REALITY_SERVER_NAME"

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
