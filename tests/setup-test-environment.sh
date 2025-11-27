#!/bin/bash

# Simple Test Setup - No Database Required
# Creates a lightweight testing environment using JWT claims directly

set -e

echo "=========================================="
echo "  Simple Test Setup (No Database)"
echo "=========================================="
echo ""

# Install prerequisites
echo "Checking and installing prerequisites..."

# Install Node.js if not present
if ! command -v node >/dev/null 2>&1; then
    echo "Installing Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
fi

# Install Nginx if not present
if ! command -v nginx >/dev/null 2>&1; then
    echo "Installing Nginx..."
    sudo apt-get update
    sudo apt-get install -y nginx
fi

echo "✓ Prerequisites installed (Node.js $(node --version), Nginx)"
echo ""

# Create test directory
mkdir -p ~/test-assets
cd ~/test-assets

# Install dependencies
echo "Installing dependencies..."
npm install express jsonwebtoken cookie-parser 2>/dev/null || npm install express jsonwebtoken cookie-parser

# Create simplified auth service (reads groups from JWT)
cat > mock-auth-service.js <<'AUTHEOF'
#!/usr/bin/env node

const express = require('express');
const jwt = require('jsonwebtoken');
const cookieParser = require('cookie-parser');

const app = express();
app.use(cookieParser());

// Secret for signing/verifying JWTs (matches token generator)
const JWT_SECRET = 'test-secret-key';

// Use regex route to match /auth/{group}/{anything}
app.get(/^\/auth\/([^\/]+)\/(.+)$/, async (req, res) => {
  const groupName = req.params[0];
  const assetPath = req.params[1];

  const jwtToken = req.cookies['jwt'];

  console.log(`[${new Date().toISOString()}] AUTH REQUEST:`);
  console.log(`  Group: ${groupName}`);
  console.log(`  Asset: ${assetPath}`);

  if (!jwtToken) {
    console.log(`  Result: ❌ DENIED (no JWT)`);
    return res.status(403).send('No JWT');
  }

  try {
    // Verify and decode JWT
    const decoded = jwt.verify(jwtToken, JWT_SECRET);

    console.log(`  User: ${decoded.email}`);
    console.log(`  Groups: ${JSON.stringify(decoded.groups)}`);

    // Check if user is in required group OR is Administrator
    if (decoded.groups.includes('Administrators') || decoded.groups.includes(groupName)) {
      if (decoded.groups.includes('Administrators')) {
        console.log(`  Result: ✅ ALLOWED (Administrator)`);
      } else {
        console.log(`  Result: ✅ ALLOWED (in group "${groupName}")`);
      }
      return res.status(200).send('OK');
    } else {
      console.log(`  Result: ❌ DENIED (not in group "${groupName}")`);
      return res.status(403).send('Access denied');
    }
  } catch (err) {
    console.log(`  Result: ❌ DENIED (invalid JWT: ${err.message})`);
    return res.status(403).send('Invalid JWT');
  }
});

app.get('/health', (req, res) => res.send('OK'));

app.listen(3002, () => {
  console.log('');
  console.log('==========================================');
  console.log('  Mock Auth Service (JWT-based)');
  console.log('==========================================');
  console.log('  Listening on: http://localhost:3002');
  console.log('  No database - uses JWT claims directly');
  console.log('==========================================');
  console.log('');
});
AUTHEOF

chmod +x mock-auth-service.js

# Create JWT token generator
cat > generate-token.js <<'JWTEOF'
#!/usr/bin/env node

const jwt = require('jsonwebtoken');

const JWT_SECRET = 'test-secret-key';

const users = {
  admin: { email: 'admin@test.com', groups: ['Administrators'] },
  manager: { email: 'manager@test.com', groups: ['managers'] },
  dev: { email: 'dev@test.com', groups: ['developers', 'managers'] },
  finance: { email: 'finance@test.com', groups: ['finance'] },
  guest: { email: 'guest@test.com', groups: [] }
};

const userType = process.argv[2];

if (!userType || !users[userType]) {
  console.error('Usage: ./generate-token.js <user>');
  console.error('Users: admin, manager, dev, finance, guest');
  process.exit(1);
}

const user = users[userType];
const token = jwt.sign({
  email: user.email,
  groups: user.groups,
  iat: Math.floor(Date.now() / 1000),
  exp: Math.floor(Date.now() / 1000) + 3600
}, JWT_SECRET);

console.log(token);
JWTEOF

chmod +x generate-token.js

# Create test files
echo "Creating test files..."
mkdir -p public-assets/images
mkdir -p secure-assets/managers
mkdir -p secure-assets/developers/project1
mkdir -p secure-assets/finance

echo "Public file - anyone can access" > public-assets/test.txt
echo "Public image" > public-assets/images/logo.txt
echo "Managers only" > secure-assets/managers/report.txt
echo "Developers only (nested)" > secure-assets/developers/project1/diagram.txt
echo "Finance only" > secure-assets/finance/budget.txt

# Set permissions so nginx (www-data) can read
chmod 755 ~/test-assets
chmod -R 755 public-assets secure-assets
find public-assets secure-assets -type f -exec chmod 644 {} \;

echo "✓ Test files created with proper permissions"
echo ""

# Set home directory permissions so nginx can traverse
echo "Setting home directory permissions..."
chmod 755 ~

# Create Nginx config
echo "Creating Nginx config..."
sudo tee /etc/nginx/sites-available/test-assets >/dev/null <<NGINXEOF
server {
    listen 8080;
    server_name localhost;

    location /public-assets/ {
        alias $HOME/test-assets/public-assets/;
        autoindex off;
    }

    location ~ ^/secure-assets/([^/]+)/(.+)$ {
        auth_request /auth-validate;
        error_page 403 = @auth_error;
        alias $HOME/test-assets/secure-assets/\$1/\$2;
        autoindex off;
    }

    location = /auth-validate {
        internal;
        set \$group_name '';
        set \$asset_path '';
        if (\$request_uri ~ "^/secure-assets/([^/]+)/(.+)\$") {
            set \$group_name \$1;
            set \$asset_path \$2;
        }
        proxy_pass http://127.0.0.1:3002/auth/\$group_name/\$asset_path;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
        proxy_set_header Cookie \$http_cookie;
    }

    location @auth_error {
        return 403 'Access Denied';
    }
}
NGINXEOF

sudo ln -sf /etc/nginx/sites-available/test-assets /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

echo ""
echo "=========================================="
echo "  Setup Complete!"
echo "=========================================="
echo ""
echo "Next Steps:"
echo "  1. Start auth service:"
echo "     nohup node ~/test-assets/mock-auth-service.js > ~/test-assets/auth.log 2>&1 &"
echo ""
echo "  2. Run tests:"
echo "     cd ~/wikijs-secure-assets && ./tests/manual-test-suite.sh"
echo ""
