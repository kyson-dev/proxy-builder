#!/bin/sh
set -e

# Check if config template exists
if [ ! -f /etc/sing-box/config.json.template ]; then
  echo "Error: config.json.template not found"
  exit 1
fi

# Check required environment variables
if [ -z "$VLESS_UUIDS" ] || [ -z "$REALITY_PRIVATE_KEY" ] || [ -z "$REALITY_SHORT_ID" ] || [ -z "$H2_PASSWORDS" ]; then
  echo "Error: Missing required environment variables"
  echo "Required: VLESS_UUIDS, REALITY_PRIVATE_KEY, REALITY_SHORT_ID, H2_PASSWORDS"
  exit 1
fi

echo "Generating configuration from template..."

# =============================================================================
# Generate VLESS users JSON
# =============================================================================
generate_vless_users() {
  local uuids="$1"
  local first=true
  local result=""
  
  echo "$uuids" | tr ',' '\n' | while read -r uuid; do
    [ -z "$uuid" ] && continue
    
    if [ "$first" = true ]; then
      first=false
    else
      printf ","
    fi
    
    printf '{"uuid":"%s","flow":"xtls-rprx-vision"}' "$uuid"
  done
}

# =============================================================================
# Generate Hysteria2 users JSON
# =============================================================================
generate_h2_users() {
  local passwords="$1"
  local first=true
  
  echo "$passwords" | tr ',' '\n' | while read -r pass; do
    [ -z "$pass" ] && continue
    
    if [ "$first" = true ]; then
      first=false
    else
      printf ","
    fi
    
    printf '{"password":"%s"}' "$pass"
  done
}

# Generate user JSON strings
VLESS_USERS_JSON=$(generate_vless_users "$VLESS_UUIDS")
H2_USERS_JSON=$(generate_h2_users "$H2_PASSWORDS")

# Validate we have at least one user for each protocol
if [ -z "$VLESS_USERS_JSON" ]; then
  echo "Error: No valid VLESS users found"
  exit 1
fi

if [ -z "$H2_USERS_JSON" ]; then
  echo "Error: No valid Hysteria2 users found"
  exit 1
fi

# Count users
VLESS_COUNT=$(echo "$VLESS_UUIDS" | tr ',' '\n' | grep -c . || echo 0)
H2_COUNT=$(echo "$H2_PASSWORDS" | tr ',' '\n' | grep -c . || echo 0)

echo "  VLESS users: $VLESS_COUNT"
echo "  Hysteria2 users: $H2_COUNT"

# Copy template
cp /etc/sing-box/config.json.template /etc/sing-box/config.json

# Replace variables using sed
sed -i "s|\${VLESS_USERS_JSON}|$VLESS_USERS_JSON|g" /etc/sing-box/config.json
sed -i "s|\${H2_USERS_JSON}|$H2_USERS_JSON|g" /etc/sing-box/config.json
sed -i "s|\${REALITY_PRIVATE_KEY}|$REALITY_PRIVATE_KEY|g" /etc/sing-box/config.json
sed -i "s|\${REALITY_SHORT_ID}|$REALITY_SHORT_ID|g" /etc/sing-box/config.json

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
