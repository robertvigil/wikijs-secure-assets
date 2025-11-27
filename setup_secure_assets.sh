#!/bin/bash

# Complete Setup Script for Wiki.js Secure Assets with Auto Group Mapping
# This creates a zero-maintenance system where folder names map to Wiki.js groups

set -e

echo "=========================================="
echo "  Wiki.js Secure Assets Setup"
echo "=========================================="
echo ""

SERVER="user@your-server.com"
SUDO_PASS="your-sudo-password"

# Check if we should proceed
read -p "This will set up group-based asset authentication. Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "Step 1: Creating directories on server..."
ssh $SERVER "mkdir -p /home/user/secure-assets/managers && \
             mkdir -p /home/user/asset-auth && \
             chmod 700 /home/user/secure-assets"
echo "✓ Directories created"

echo ""
echo "Step 2: Copying example file to secure folder..."
ssh $SERVER "cp /home/user/wiki/data/cache/[EXAMPLE_HASH].dat /home/user/secure-assets/managers/report.pdf"
echo "✓ File copied"

echo ""
echo "Step 3: Uploading auth service..."
scp asset-auth-service.js $SERVER:/home/user/asset-auth/
ssh $SERVER "chmod +x /home/user/asset-auth/asset-auth-service.js"
echo "✓ Auth service uploaded"

echo ""
echo "Step 4: Installing Node.js dependencies..."
ssh $SERVER "cd /home/user/asset-auth && npm install express pg cookie-parser 2>&1"
echo "✓ Dependencies installed"

echo ""
echo "Step 5: Creating systemd service..."
cat > /tmp/asset-auth.service << 'EOF'
[Unit]
Description=Wiki.js Asset Authentication Service
After=network.target postgresql.service

[Service]
Type=simple
User=user
WorkingDirectory=/home/user/asset-auth
ExecStart=/usr/bin/node /home/user/asset-auth/asset-auth-service.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

scp /tmp/asset-auth.service $SERVER:/tmp/
echo "$SUDO_PASS" | ssh $SERVER "echo '$SUDO_PASS' | sudo -S mv /tmp/asset-auth.service /etc/systemd/system/"
echo "✓ Service file created"

echo ""
echo "Step 6: Creating Nginx configuration..."
cat > /tmp/secure-assets.conf << 'EOF'
# Secure Assets with Auto Group Mapping
# Pattern: /secure-assets/{GROUP_NAME}/{FILENAME}
# Example: /secure-assets/managers/report.pdf requires user in "managers" group

location ~ ^/secure-assets/([^/]+)/(.+)$ {
    # $1 = group name (e.g., "managers")
    # $2 = asset path (e.g., "report.pdf")

    # Validate user is in the required group
    auth_request /auth-validate;
    auth_request_set $auth_status $upstream_status;

    # Error handling
    error_page 403 = @auth_error;

    # Serve from disk
    alias /home/user/secure-assets/$1/$2;

    # Security headers
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options SAMEORIGIN;

    # Cache for authenticated users
    expires 1h;
    add_header Cache-Control "private, must-revalidate";

    # Disable autoindex
    autoindex off;
}

# Internal auth validation endpoint
location ~ ^/auth-validate$ {
    internal;

    # Extract group and asset from original URI
    set $group_name '';
    set $asset_path '';

    if ($request_uri ~ "^/secure-assets/([^/]+)/(.+)$") {
        set $group_name $1;
        set $asset_path $2;
    }

    # Call auth service
    proxy_pass http://localhost:3002/auth/$group_name/$asset_path;
    proxy_pass_request_body off;
    proxy_set_header Content-Length "";
    proxy_set_header Cookie $http_cookie;
    proxy_set_header X-Original-URI $request_uri;
}

# Auth error page
location @auth_error {
    return 403 "Access denied: Check Wiki.js login and group membership";
}
EOF

scp /tmp/secure-assets.conf $SERVER:/tmp/
echo "✓ Nginx config created"

echo ""
echo "Step 7: Backing up current Nginx config..."
echo "$SUDO_PASS" | ssh $SERVER "echo '$SUDO_PASS' | sudo -S cp /etc/nginx/sites-available/wiki /etc/nginx/sites-available/wiki.backup.$(date +%Y%m%d-%H%M%S)"
echo "✓ Backup created"

echo ""
echo "Step 8: Installing Nginx config..."
echo "$SUDO_PASS" | ssh $SERVER "echo '$SUDO_PASS' | sudo -S mv /tmp/secure-assets.conf /etc/nginx/conf.d/"
echo "✓ Config installed"

echo ""
echo "Step 9: Testing Nginx configuration..."
echo "$SUDO_PASS" | ssh $SERVER "echo '$SUDO_PASS' | sudo -S nginx -t"
echo "✓ Nginx config valid"

echo ""
echo "Step 10: Starting services..."
echo "$SUDO_PASS" | ssh $SERVER "echo '$SUDO_PASS' | sudo -S systemctl daemon-reload"
echo "$SUDO_PASS" | ssh $SERVER "echo '$SUDO_PASS' | sudo -S systemctl enable asset-auth"
echo "$SUDO_PASS" | ssh $SERVER "echo '$SUDO_PASS' | sudo -S systemctl start asset-auth"
echo "$SUDO_PASS" | ssh $SERVER "echo '$SUDO_PASS' | sudo -S systemctl reload nginx"
echo "✓ Services started"

echo ""
echo "Step 11: Checking service status..."
sleep 2
echo "$SUDO_PASS" | ssh $SERVER "echo '$SUDO_PASS' | sudo -S systemctl status asset-auth --no-pager -l" | head -15

echo ""
echo "=========================================="
echo "  ✓ Setup Complete!"
echo "=========================================="
echo ""
echo "Test URL:"
echo "  https://your-server.com/secure-assets/managers/report.pdf"
echo ""
echo "Expected behavior:"
echo "  - Logged in as user in 'managers' group: ✅ File displays"
echo "  - Logged in as user NOT in 'managers' group: ❌ 403 Forbidden"
echo "  - Not logged in: ❌ 403 Forbidden"
echo ""
echo "Usage in Wiki.js pages:"
echo "  <img src=\"/secure-assets/managers/report.pdf\">"
echo ""
echo "Add more protected folders:"
echo "  mkdir /home/user/secure-assets/vacation"
echo "  cp image.jpg /home/user/secure-assets/vacation/"
echo "  → Automatically requires 'vacation' group!"
echo ""
echo "View auth service logs:"
echo "  ssh $SERVER 'sudo journalctl -u asset-auth -f'"
echo ""
