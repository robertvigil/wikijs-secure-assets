#!/bin/bash

# Production server verification before running setup

echo "=========================================="
echo "  Production Server Verification"
echo "=========================================="
echo ""

SERVER="${WIKI_SERVER:-user@your-server.com}"
ERRORS=0

echo "1. Checking SSH connection..."
if ssh -o ConnectTimeout=5 $SERVER "echo 'OK'" > /dev/null 2>&1; then
    echo "   ✓ SSH connection working"
else
    echo "   ✗ SSH connection failed"
    ERRORS=$((ERRORS + 1))
fi

echo ""
echo "2. Checking Wiki.js database..."
DB_CHECK=$(ssh $SERVER "sudo -u postgres psql -d wikijs -c 'SELECT COUNT(*) FROM users;' 2>&1" | grep -c "ERROR")
if [ "$DB_CHECK" -eq 0 ]; then
    echo "   ✓ Database accessible"
else
    echo "   ✗ Database connection failed"
    ERRORS=$((ERRORS + 1))
fi

echo ""
echo "3. Checking Node.js..."
NODE_VERSION=$(ssh $SERVER "node --version 2>&1")
if [[ $NODE_VERSION == v* ]]; then
    echo "   ✓ Node.js installed: $NODE_VERSION"
else
    echo "   ✗ Node.js not found"
    ERRORS=$((ERRORS + 1))
fi

echo ""
echo "4. Checking Nginx..."
NGINX_CHECK=$(ssh $SERVER "which nginx 2>&1")
if [[ $NGINX_CHECK == /*/nginx ]]; then
    echo "   ✓ Nginx installed: $NGINX_CHECK"
else
    echo "   ✗ Nginx not found"
    ERRORS=$((ERRORS + 1))
fi

echo ""
echo "5. Checking Wiki.js groups..."
GROUPS=$(ssh $SERVER "sudo -u postgres psql -d wikijs -t -c \"SELECT name FROM groups;\" 2>&1" | grep -v "^$" | tr '\n' ',' | sed 's/,$//')
echo "   Available groups: $GROUPS"
echo "   ℹ  You'll configure folder-to-group mapping during setup"

echo ""
echo "6. Checking if port 3002 is available..."
PORT_CHECK=$(ssh $SERVER "sudo lsof -i :3002 2>&1" | grep -c "LISTEN")
if [ "$PORT_CHECK" -eq 0 ]; then
    echo "   ✓ Port 3002 available"
else
    echo "   ⚠ Port 3002 already in use"
fi

echo ""
echo "7. Checking disk space..."
DISK_USAGE=$(ssh $SERVER "df -h /home/user | tail -1 | awk '{print \$5}'" | sed 's/%//')
echo "   Disk usage: ${DISK_USAGE}%"
if [ "$DISK_USAGE" -lt 90 ]; then
    echo "   ✓ Sufficient disk space"
else
    echo "   ⚠ Disk usage high"
fi

echo ""
echo "8. Checking asset-auth service..."
AUTH_STATUS=$(ssh $SERVER "systemctl is-active asset-auth 2>&1")
if [ "$AUTH_STATUS" = "active" ]; then
    echo "   ✓ Asset-auth service running"

    # Check JWT verification is enabled
    JWT_CHECK=$(ssh $SERVER "journalctl -u asset-auth -n 20 --no-pager 2>&1" | grep -c "JWT Verification: ENABLED")
    if [ "$JWT_CHECK" -gt 0 ]; then
        echo "   ✓ JWT signature verification enabled"
    else
        echo "   ⚠ JWT verification status unknown"
    fi
else
    echo "   ℹ  Asset-auth service not running (normal if not yet installed)"
fi

echo ""
echo "9. Testing JWT security (if service installed)..."
if [ "$AUTH_STATUS" = "active" ]; then
    # Test with spoofed JWT
    HEADER="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
    PAYLOAD="eyJpZCI6MSwiZW1haWwiOiJhZG1pbkBmYWtlLmNvbSJ9"
    SIGNATURE="FAKE_SIGNATURE"
    FAKE_JWT="${HEADER}.${PAYLOAD}.${SIGNATURE}"

    HTTP_CODE=$(curl -s -w "%{http_code}" -o /dev/null \
        --cookie "jwt=${FAKE_JWT}" \
        https://robertvigil.com/secure-assets/30days/sink1.png 2>/dev/null)

    if [ "$HTTP_CODE" = "403" ]; then
        echo "   ✓ Spoofed JWT correctly rejected (HTTP 403)"
        echo "   ✓ JWT signature verification working"
    else
        echo "   ✗ Security issue: Spoofed JWT not rejected (HTTP $HTTP_CODE)"
        ERRORS=$((ERRORS + 1))
    fi

    # Test without JWT
    HTTP_CODE=$(curl -s -w "%{http_code}" -o /dev/null \
        https://robertvigil.com/secure-assets/30days/sink1.png 2>/dev/null)

    if [ "$HTTP_CODE" = "403" ]; then
        echo "   ✓ No JWT correctly blocked (HTTP 403)"
    else
        echo "   ⚠ Unexpected response without JWT (HTTP $HTTP_CODE)"
    fi
else
    echo "   ℹ  Skipping (service not installed)"
fi

echo ""
echo "=========================================="
if [ $ERRORS -eq 0 ]; then
    echo "  ✓ All checks passed!"
    echo "=========================================="
    echo ""
    echo "Ready to run: ./setup_secure_assets.sh"
    exit 0
else
    echo "  ✗ $ERRORS check(s) failed"
    echo "=========================================="
    echo ""
    echo "Please fix errors before running setup."
    exit 1
fi
