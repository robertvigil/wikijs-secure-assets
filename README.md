# Wiki.js Secure Assets

Group-based asset authentication for Wiki.js with automatic folder-to-group mapping and JWT signature verification.

## Table of Contents

- [Overview](#overview)
- [Key Features](#key-features)
- [Quick Start](#quick-start)
- [How It Works](#how-it-works)
- [Installation](#installation)
- [Usage](#usage)
- [Configuration](#configuration)
- [Security](#security)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)
- [Performance](#performance)
- [Advanced Topics](#advanced-topics)
- [Testing](#testing)

## Overview

A solution for protecting Wiki.js assets with group-based permissions. **Zero maintenance** - folder names automatically map to Wiki.js groups.

```
URL Pattern: /secure/{GROUP_NAME}/{PATH}

Examples:
/secure/mgmt/report.pdf             → Requires "mgmt" group OR admin
/secure/dev/diagram.png             → Requires "dev" group OR admin
/secure/finance/budget.xlsx         → Requires "finance" group OR admin
/secure/developers/project1/        → Directory with index.html (if exists)
/secure/developers/project1/doc.pdf → Nested file in subdirectory
```

**URL Paths:** Use `/secure/` and `/public/` in your Wiki.js pages and URLs. These map to the `secure-assets/` and `public-assets/` directories on disk.

**Special Rule:** Users in the "admin" group (or "Administrators" for Wiki.js compatibility) have access to ALL assets regardless of folder name.

**Group Naming:** Use short, lowercase group names (e.g., `admin`, `dev`, `mgmt`, `view`) for clean URLs. The system maintains backwards compatibility with Wiki.js by accepting both "admin" and "Administrators" as admin groups.

## Key Features

- **Automatic mapping** - Folder name determines required group
- **JWT authentication** - RS256 cryptographic signature verification prevents token spoofing
- **Multi-group support** - Users can belong to multiple groups
- **Administrator privilege** - Full access to all assets for admins
- **Mixed permissions** - Pages can have images from different folders
- **Nginx-based** - Files served directly after auth check (high performance)
- **Dynamic RSA key loading** - Public key loaded from database, no hardcoded credentials
- **Tested with** - Wiki.js 2.5.308, Ubuntu 24.04, Node.js 20, Nginx 1.24

## Quick Start

### Installation

```bash
# 1. Verify prerequisites
cd /path/to/wikijs-secure-assets
./tests/verify-production-server.sh

# 2. Run automated setup
./setup_secure_assets.sh
```

The setup script will:
- Create folder structure
- Install auth service with dependencies
- Configure Nginx
- Create systemd service
- Start services

### Basic Usage

```bash
# 1. Create folder matching Wiki.js group name
mkdir -p /home/user/secure-assets/contractors
chmod 755 /home/user/secure-assets/contractors

# 2. Add images
cp sensitive-doc.pdf /home/user/secure-assets/contractors/
chmod 644 /home/user/secure-assets/contractors/sensitive-doc.pdf

# 3. Use in Wiki.js pages
<img src="/secure/contractors/sensitive-doc.pdf">
```

That's it! The folder name automatically maps to the group - no configuration needed.

## How It Works

### Authentication Flow

```
1. User requests: /secure/managers/report.pdf
2. Nginx rewrites internally to: /secure-assets/managers/report.pdf
3. Nginx calls auth service via auth_request
4. Auth service validates:
   ├─ Extracts JWT from 'jwt' cookie
   ├─ Verifies JWT signature (HMAC-SHA256)
   ├─ Decodes JWT to get user ID
   └─ Queries database for group membership
5. If authorized → Nginx serves file from disk
   If unauthorized → Returns 403 Forbidden
```

### Components

#### 1. Auth Service (`asset-auth-service.js`)
- **Technology:** Node.js + Express
- **Port:** 3002 (localhost only)
- **Purpose:** JWT validation and group membership checks
- **Database:** PostgreSQL (Wiki.js database)

**Security Features:**
- Cryptographic JWT signature verification using `jwt.verify()`
- Dynamic RSA public key loading from Wiki.js database (`settings.certs`)
- Prevents token spoofing and tampering
- RS256 (RSA-SHA256) asymmetric encryption algorithm

**Dependencies:**
```bash
npm install express pg cookie-parser jsonwebtoken
```

#### 2. Nginx Configuration
- **Location:** `/etc/nginx/sites-available/wiki` (integrated into main config)
- **Purpose:** Intercepts `/secure/*` and `/public/*` requests
- **Method:** Uses `auth_request` directive for secure assets
- **Serving:** Direct file serving after authorization (no Node.js overhead)

#### 3. File Structure

```
/home/user/
├── public-assets/           (755)  # No auth required
│   └── images/             (755)
│       └── logo.png        (644)
├── secure-assets/           (755)  # Group-based auth
│   ├── managers/           (755)
│   │   ├── report.pdf      (644)
│   │   └── project1/       (755)  # Nested folders supported
│   │       └── doc.pdf     (644)
│   ├── developers/         (755)
│   │   └── diagram.png     (644)
│   └── {GROUP_NAME}/       (755)
│       └── files...        (644)
```

**Critical:** Home directory must have execute permission (751) for www-data to traverse.

## Installation

### Automated Setup (Recommended)

```bash
cd /path/to/wikijs-secure-assets
./setup_secure_assets.sh
```

### Manual Setup

#### 1. Create Folder Structure

```bash
ssh user@your-server.com
mkdir -p /home/user/secure-assets/managers
chmod 755 /home/user/secure-assets
chmod 755 /home/user/secure-assets/managers
```

#### 2. Install Auth Service

```bash
# Upload service
scp asset-auth-service.js user@your-server.com:/home/user/asset-auth/

# Install dependencies
ssh user@your-server.com
cd /home/user/asset-auth
npm install express pg cookie-parser jsonwebtoken
```

#### 3. Create Systemd Service

Create `/etc/systemd/system/asset-auth.service`:

```ini
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

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable asset-auth
sudo systemctl start asset-auth
```

#### 4. Configure Nginx

Add to your Wiki.js server block in `/etc/nginx/sites-available/wiki`:

```nginx
# Public assets (no authentication required)
location /public-assets/ {
    alias /home/user/public-assets/;
    autoindex off;
    add_header Cache-Control "public, max-age=3600";
}

# Auth service endpoint (internal only)
location = /auth-validate {
    internal;
    proxy_pass http://127.0.0.1:3002/auth/$group_name/$asset_path;
    proxy_pass_request_body off;
    proxy_set_header Content-Length "";
    proxy_set_header X-Original-URI $request_uri;
}

# Secure assets with group-based auth
location ~ ^/secure-assets/(?<group_name>[^/]+)/(?<asset_path>.+)$ {
    auth_request /auth-validate;

    alias /home/user/secure-assets/$group_name/$asset_path;

    add_header Cache-Control "private, no-cache, must-revalidate";
    add_header X-Group-Required $group_name;
}
```

Test and reload:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

## Usage

### Adding Protected Assets

```bash
# 1. Create folder named after Wiki.js group
mkdir -p /home/user/secure-assets/vacation

# 2. Add images to that folder
cp beach.jpg /home/user/secure-assets/vacation/
chmod 644 /home/user/secure-assets/vacation/beach.jpg

# 3. Use in Wiki.js pages
<img src="/secure/vacation/beach.jpg">

# That's it! Automatically requires "vacation" group membership
```

### Using in Wiki.js Pages

#### Visual Editor Mode
1. Edit page
2. Insert image
3. Use URL: `/secure/managers/report.pdf`

#### Source/HTML Mode
```html
<img src="/secure/managers/report.pdf" alt="Manager Report">
```

#### Markdown Mode
```markdown
![Manager Report](/secure/managers/report.pdf)
```

### Creating New Protected Groups

```bash
# 1. Create Wiki.js group (if doesn't exist)
#    Admin → Groups → Create "contractors"

# 2. Create matching folder
mkdir /home/user/secure-assets/contractors
chmod 755 /home/user/secure-assets/contractors

# 3. Add images
cp project-plans.pdf /home/user/secure-assets/contractors/
chmod 644 /home/user/secure-assets/contractors/project-plans.pdf

# 4. Use in pages restricted to "contractors" group
<img src="/secure/contractors/project-plans.pdf">
```

**Zero configuration needed!** The folder name automatically maps to the group.

### Public vs Secure Assets

#### Public Assets
No authentication required - anyone can access:

```bash
# Create folder structure
mkdir -p /home/user/public-assets/images/logos
chmod 755 /home/user/public-assets/images/logos

# Add files
cp logo.png /home/user/public-assets/images/logos/
chmod 644 /home/user/public-assets/images/logos/logo.png

# Use in Wiki.js
<img src="/public/images/logos/logo.png">
```

#### Secure Assets with Nested Folders
Group-based authentication - supports nested folders:

```bash
# Create nested folder structure
mkdir -p /home/user/secure-assets/developers/project1/diagrams
chmod 755 /home/user/secure-assets/developers
chmod 755 /home/user/secure-assets/developers/project1
chmod 755 /home/user/secure-assets/developers/project1/diagrams

# Add files at any depth
cp diagram.png /home/user/secure-assets/developers/project1/diagrams/
chmod 644 /home/user/secure-assets/developers/project1/diagrams/diagram.png

# Use in Wiki.js - only "developers" group can access
<img src="/secure/developers/project1/diagrams/diagram.png">
```

The first folder (`developers`) determines the group - all subfolders inherit that permission.

## Configuration

### File Permissions Requirements

**Critical:** Nginx runs as `www-data` and must be able to read the asset files.

```bash
# Home directory - needs execute permission for traversal
chmod 751 /home/user

# Public assets directory and subdirectories
chmod 755 /home/user/public-assets
chmod 755 /home/user/public-assets/{SUBFOLDER}

# Secure assets directory and subdirectories
chmod 755 /home/user/secure-assets
chmod 755 /home/user/secure-assets/{GROUP_NAME}

# Individual files
chmod 644 /home/user/public-assets/{SUBFOLDER}/*
chmod 644 /home/user/secure-assets/{GROUP_NAME}/*
```

**Test if www-data can read:**
```bash
# Test public assets
sudo -u www-data test -r /home/user/public-assets/logo.png && echo "OK" || echo "FAIL"

# Test secure assets
sudo -u www-data test -r /home/user/secure-assets/managers/report.pdf && echo "OK" || echo "FAIL"
```

### Authentication Method

- **Wiki.js uses JWT tokens**, not session-based authentication
- Auth service reads the `jwt` cookie (NOT `wikijs.sid`)
- **JWT signature verification**: Cryptographically validates tokens using Wiki.js RSA public key
  - Public key is dynamically loaded from Wiki.js database at startup (`settings.certs`)
  - Prevents token spoofing - invalid signatures are rejected
  - Uses RS256 (RSA-SHA256) asymmetric algorithm to verify token authenticity
  - Wiki.js signs tokens with its private key; auth service verifies with public key
- JWT is verified and decoded to extract user ID, then database is queried for group membership

### Caching Behavior

- **Cache-Control:** `private, no-cache, must-revalidate`
- Browsers cache images but revalidate authentication on each request
- Prevents showing cached images after logout
- Use **Ctrl+F5** (hard refresh) to clear cached images when testing

### Error Handling

- **Unauthorized access:** Returns HTTP 403 with error message
- **No redirect:** User stays on page even if some images are denied
- **Mixed permissions:** Pages can have images from multiple folders - users see only what they have access to

## Security

### What's Protected

✅ Direct URL access requires authentication
✅ Group-level permissions enforced
✅ JWT signature verification (cryptographically validates tokens)
✅ Protection against token spoofing (invalid signatures rejected)
✅ Session validation (checks Wiki.js login)
✅ Prevents unauthorized access
✅ Admin users have full access (checks both "admin" and "Administrators" groups)

### What's NOT Protected

⚠️ **Image data in page source** - Authenticated users can view images, download, or inspect network requests
⚠️ **No time-limited URLs** - Access lasts as long as session is valid
⚠️ **Same-server storage** - Images stored on same machine as Wiki.js
⚠️ **No audit trail** - No logging of who accessed which assets

### Best Practices

1. **Use for confidential-but-not-secret content**
   - Internal diagrams ✅
   - Project screenshots ✅
   - Team photos ✅
   - Passwords/keys/secrets ❌

2. **Folder naming**
   - Keep folder names simple (no spaces, special chars)
   - Match Wiki.js group names exactly (case-sensitive)

3. **File cleanup**
   - Delete original assets from Wiki.js after moving to secure-assets
   - Prevents bypassing security via old URLs

4. **Backup**
   - Include `/home/user/secure-assets/` in backup routine
   - Images are on disk, not in database

### JWT Security Details

**How JWT Verification Works:**

A JWT token has 3 parts: `[HEADER].[PAYLOAD].[SIGNATURE]`

```javascript
// Example JWT verification process (RS256)
jwt.verify(token, PUBLIC_KEY) performs:

1. Decrypt the signature with public key
   original_hash = RSA_decrypt(signature, PUBLIC_KEY)

2. Hash the header + payload
   computed_hash = SHA256(header + "." + payload)

3. Compare the hashes
   if (original_hash === computed_hash) {
     // Valid - signed by Wiki.js with private key
   } else {
     // Invalid - reject as forgery or tampering
   }

// Note: The payload is NOT encrypted - it's base64 encoded and readable
// Only the hash is encrypted (signed) to prove authenticity
```

**Security Guarantee:**
- Only Wiki.js can create valid signatures (has the private key)
- Attackers can't forge signatures without the private key
- Tampering with payload invalidates signature
- Public key dynamically loaded from database (no hardcoded keys)
- Asymmetric encryption means public key can be shared safely

## Monitoring

### View Auth Service Logs

```bash
# Real-time logs
sudo journalctl -u asset-auth -f

# Recent logs
sudo journalctl -u asset-auth -n 50

# Example output:
[2025-11-23T11:30:15.123Z] AUTH REQUEST:
  Group: managers
  Asset: report.pdf
  User ID from JWT: 123
  Email from JWT: user@example.com
  User: user@example.com
  Result: ✅ ALLOWED (in group "managers")
```

### Service Management

```bash
# Check status
sudo systemctl status asset-auth
sudo systemctl status nginx

# Start/Stop/Restart
sudo systemctl restart asset-auth
sudo systemctl reload nginx  # Zero-downtime reload

# Enable autostart
sudo systemctl enable asset-auth
```

## Troubleshooting

### Image shows 403 Forbidden

**Possible causes:**

1. **Not logged in**
   - Solution: Log into Wiki.js first

2. **Not in required group**
   - Check: Admin → Groups → Find user
   - Solution: Add user to group matching folder name

3. **Service not running**
   ```bash
   sudo systemctl status asset-auth
   sudo systemctl start asset-auth
   ```

4. **Wrong folder name**
   - Folder name must exactly match Wiki.js group name (case-sensitive)
   - Check: `ls /home/user/secure-assets/`
   - Check: Wiki.js Admin → Groups

5. **File permissions**
   ```bash
   # Files should be readable
   chmod 644 /home/user/secure-assets/managers/report.pdf

   # Directories need execute permission for www-data to traverse
   chmod 755 /home/user/secure-assets
   chmod 755 /home/user/secure-assets/managers

   # Home directory needs execute permission for "others"
   chmod 751 /home/user
   ```

### Intermittent 403s after a period of inactivity

**Symptom:** secure asset works for a while, then fails with 403. Loading or refreshing any other Wiki.js tab (e.g., the main robertvigil.com page) and then refreshing the failed asset tab makes it work again.

**Cause:** Wiki.js issues short-lived JWTs (default `tokenExpiration: 30m`) and refreshes them silently as you use the SPA. The asset-auth service has no refresh logic — it just verifies the cookie's signature and TTL, so an expired JWT returns 403 ("JWT expired" in the auth service logs). When you reload a Wiki.js tab, the SPA's session logic mints a fresh JWT and writes it to the `jwt` cookie. Cookies are domain-scoped, so the new cookie is immediately available to *all* tabs on robertvigil.com, including the asset tab.

**Quick workaround:** reload any Wiki.js page on the same domain, then reload the asset.

**Permanent fix — bump the JWT TTL.** Wiki.js stores `tokenExpiration` as JSON in the `settings` table (key `auth`). To extend to e.g. 2 hours:

```bash
ssh rvigil@robertvigil.com

# Inspect the current value first
sudo -u postgres psql wikijs -c "SELECT jsonb_pretty(value::jsonb) FROM settings WHERE key = 'auth';"

# Update to 2h (the value column is type json, not text or jsonb — note the ::json cast)
sudo -u postgres psql wikijs -c "UPDATE settings SET value = jsonb_set(value::jsonb, '{tokenExpiration}', '\"2h\"')::json WHERE key = 'auth';"

# Restart Wiki.js so new logins pick up the change
sudo systemctl restart wiki

# Verify
sudo -u postgres psql wikijs -c "SELECT value::jsonb->>'tokenExpiration' FROM settings WHERE key = 'auth';"
# → 2h
```

Accepted formats follow [zeit/ms](https://github.com/vercel/ms): `2h`, `4h`, `8h`, `1d`, etc. The companion field `tokenRenewal` (default `14d`) is the refresh-token window — leave it alone unless you know why you're touching it.

**Two caveats:**

- **Existing tokens keep their old TTL** — they were minted with the old expiry baked in. Log out and log back in after the restart to get a fresh JWT with the new TTL.
- **Decode the cookie at [jwt.io](https://jwt.io)** to confirm: `exp - iat` should equal the new TTL in seconds (7200 for 2h).

The auth service code itself doesn't need changes — it reads whatever expiry Wiki.js encodes in the JWT.

### Image not found (404)

1. **Check file exists**
   ```bash
   ls -la /home/user/secure-assets/managers/report.pdf
   ```

2. **Check path in URL**
   - Must match: `/secure/{GROUP}/{FILENAME}`
   - Case-sensitive

### Database connection errors

```bash
# Check auth service logs
sudo journalctl -u asset-auth -n 20

# Test database connection
PGPASSWORD='wikijspassword' psql -U wikijs -h localhost -d wikijs -c "SELECT COUNT(*) FROM users;"
```

### Nginx errors

```bash
# Check Nginx error log
sudo tail -f /var/log/nginx/error.log

# Test configuration
sudo nginx -t
```

### Image cached after logout

Use hard refresh:
- **Windows/Linux:** Ctrl+F5
- **Mac:** Cmd+Shift+R

### Mixed Permissions on Same Page

**Scenario:** Page has images from multiple secure folders (e.g., vacation and managers)

**Behavior:**
- Images from groups you belong to: ✅ Display correctly
- Images from groups you don't belong to: ❌ Show as broken images
- You stay on the page (no redirect to login)

**This is expected behavior.** Users will only see images from folders matching their group memberships.

## Performance

### Benchmarks

- **Auth validation:** ~5-10ms per request
- **Image serving:** Nginx direct (fast, no Node.js overhead)
- **Database queries:** Indexed, very fast (<5ms)
- **JWT verification:** ~1-2ms per request

### Caching

- **Browser cache:** 1 hour (for authenticated users)
- **No CDN caching:** Images always served through auth check
- **Session cache:** Wiki.js handles session caching

### Scalability

- Auth service is lightweight (Node.js + PostgreSQL)
- Can handle hundreds of concurrent requests
- For higher scale: Add Redis caching or multiple auth service instances

## Advanced Topics

### Examples

#### Multi-Group Membership

User belongs to: `["mgmt", "dev", "admin"]`

- `/secure/managers/report.pdf` → Allowed (in "managers")
- `/secure/developers/diagram.png` → Allowed (in "developers")
- `/secure/finance/budget.xlsx` → Allowed (Administrator)
- `/secure/other/file.png` → Allowed (Administrator)

#### Mixed Permissions Page

Page contains:
```html
<img src="/secure/managers/report.png">
<img src="/secure/developers/diagram.png">
```

User in "managers" group only:
- managers image: Displays
- developers image: Shows as broken
- User stays on page (no redirect)

### Migration from Public Wiki.js Assets

```bash
# 1. Find asset in database
sudo -u postgres psql -d wikijs -c "SELECT id, filename, hash FROM assets WHERE filename = 'report.pdf';"

# 2. Copy from cache to secure folder
cp /home/user/wiki/data/cache/[HASH].dat /home/user/secure-assets/managers/report.pdf

# 3. Update Wiki.js pages to use new URL
# 4. Delete old asset from Wiki.js
```

### External Identity Providers (Auth0, Okta, etc.)

This secure assets system **remains fully compatible** when Wiki.js is configured to use external identity providers like Auth0, Okta, Keycloak, or any OIDC/SAML provider.

**Why it still works:**

```
Authentication Flow with External IdP:

User → Auth0/Okta login → Redirects back to Wiki.js → Wiki.js creates session
                                                    → Wiki.js issues its own JWT
                                                    → Stored in 'jwt' cookie
                                                    → asset-auth-service validates Wiki.js JWT ✓
```

The external identity provider handles **authentication** (verifying who the user is), but Wiki.js still:

1. **Creates/links local user records** in its database
2. **Manages group membership** (groups are still Wiki.js groups)
3. **Issues its own JWT tokens** signed with its RSA keys
4. **Stores the JWT** in the `jwt` cookie

| Component | With Local Auth | With External IdP (Auth0, etc.) |
|-----------|-----------------|----------------------------------|
| JWT cookie | Wiki.js issues | Wiki.js still issues |
| JWT signing key | Wiki.js RSA key | Same Wiki.js RSA key |
| User ID in JWT | Wiki.js user ID | Same Wiki.js user ID |
| Group membership | Wiki.js database | Same Wiki.js database |
| asset-auth-service | Validates Wiki.js JWT | Still validates Wiki.js JWT |

**Key point:** The asset-auth-service validates **Wiki.js tokens**, not Auth0/Okta tokens. The external provider is just the "front door" for authentication - Wiki.js still manages sessions and authorization.

**No changes required** to this secure assets system when adding an external identity provider to Wiki.js.

### Uninstall

```bash
# Stop and disable service
sudo systemctl stop asset-auth
sudo systemctl disable asset-auth
sudo rm /etc/systemd/system/asset-auth.service
sudo systemctl daemon-reload

# Remove Nginx config
# (Remove the location blocks from /etc/nginx/sites-available/wiki)
sudo nginx -t
sudo systemctl reload nginx

# Remove files (optional - keeps images safe)
rm -rf /home/user/asset-auth
# rm -rf /home/user/secure-assets  # Careful - deletes images!
```

## Testing

For comprehensive testing documentation, see **[tests/README.md](tests/README.md)**

### Quick Production Verification

```bash
# Verify server is ready
./tests/verify-production-server.sh
```

This will check:
- SSH connection
- Database access
- Node.js and Nginx installation
- Port availability
- Asset-auth service status
- JWT security (spoofed token rejection)

## Architecture

**Tech Stack:**
- Wiki.js 2.5+ (content management system)
- Node.js 20+ (Express.js for auth service)
- PostgreSQL (Wiki.js database)
- Nginx (reverse proxy with auth_request)
- JWT authentication (HMAC-SHA256)

**Repository Structure:**
```
wikijs-secure-assets/
├── README.md                    # This file
├── asset-auth-service.js        # Auth service
├── setup_secure_assets.sh       # Automated installer
└── tests/                       # Testing materials
    ├── README.md                # Testing guide
    ├── verify-production-server.sh
    └── ...
```

## License

MIT License - See LICENSE file for details

## Credits

- Wiki.js: https://js.wiki/

---

**Version:** 1.0
**Last Updated:** November 25, 2025
**Tested with:** Wiki.js 2.5.308, Ubuntu 24.04, Nginx 1.24, Node.js 20
