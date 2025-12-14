#!/bin/sh
set -e

# Check if config template exists
if [ ! -f /etc/nginx/nginx.conf.template ]; then
  echo "Error: nginx.conf.template not found"
  exit 1
fi

# Check required environment variables
if [ -z "$DOMAIN" ]; then
  echo "Error: DOMAIN environment variable is missing."
  exit 1
fi

echo "Generating Nginx configuration from template..."

# Copy template
cp /etc/nginx/nginx.conf.template /etc/nginx/nginx.conf

# Replace variables using sed
sed -i "s|\${DOMAIN}|$DOMAIN|g" /etc/nginx/nginx.conf

echo "Nginx configuration generated successfully."

# Validate configuration
echo "Validating Nginx configuration..."
if ! nginx -t; then
  echo "Error: Invalid Nginx configuration generated."
  echo "Dumping generated configuration for debugging:"
  cat /etc/nginx/nginx.conf
  exit 1
fi

# Start Nginx
echo "Starting Nginx..."
exec nginx -g 'daemon off;'
