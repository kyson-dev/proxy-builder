#!/bin/sh
set -e

# Check if config template exists
if [ ! -f /etc/sing-box/config.json.template ]; then
  echo "Error: config.json.template not found"
  exit 1
fi

# Check required environment variables
if [ -z "$VLESS_USERS" ] || [ -z "$REALITY_PRIVATE_KEY" ] || [ -z "$REALITY_SHORT_ID" ] || [ -z "$H2_USERS" ]; then
  echo "Error: Missing required environment variables"
  echo "Required: VLESS_USERS (JSON), H2_USERS (JSON), REALITY_PRIVATE_KEY, REALITY_SHORT_ID"
  exit 1
fi

echo "Generating configuration from template..."

# Check if inputs are valid JSON (basic check)
if ! echo "$VLESS_USERS" | grep -q '^\['; then
  echo "Error: VLESS_USERS must be a JSON array starting with ["
  exit 1
fi

if ! echo "$H2_USERS" | grep -q '^\['; then
  echo "Error: H2_USERS must be a JSON array starting with ["
  exit 1
fi

echo "  VLESS users configured (JSON)"
echo "  Hysteria2 users configured (JSON)"

# Copy template
cp /etc/sing-box/config.json.template /etc/sing-box/config.json

# Replace variables using sed
# Note: Use different delimiter for sed to avoid issues with special chars
# We use a temporary file to handle multiline JSON strings correctly with sed
sed -i "s|\${REALITY_PRIVATE_KEY}|$REALITY_PRIVATE_KEY|g" /etc/sing-box/config.json
sed -i "s|\${REALITY_SHORT_ID}|$REALITY_SHORT_ID|g" /etc/sing-box/config.json

# For JSON arrays, we use awkward implementation to prevent sed from breaking on newlines
# 1. Escape newlines in the JSON string
VLESS_USERS_ESCAPED=$(echo "$VLESS_USERS" | tr '\n' ' ' | sed 's/  */ /g')
H2_USERS_ESCAPED=$(echo "$H2_USERS" | tr '\n' ' ' | sed 's/  */ /g')

sed -i "s|\${VLESS_USERS}|$VLESS_USERS_ESCAPED|g" /etc/sing-box/config.json
sed -i "s|\${H2_USERS}|$H2_USERS_ESCAPED|g" /etc/sing-box/config.json

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
