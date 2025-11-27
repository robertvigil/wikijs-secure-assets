# Testing Guide

Test the secure assets system in both local and production environments.

## Table of Contents

- [Local Testing (Multipass)](#local-testing-multipass)
- [Production Verification](#production-verification)
- [Manual Test Suite](#manual-test-suite)
- [Test Scenarios](#test-scenarios)
- [Troubleshooting](#troubleshooting)

## Local Testing (Multipass)

Test in a clean environment without installing Wiki.js.

### 1. Create Clean Test Instance

```bash
# On your local machine
multipass launch --name wikijs-test --cpus 2 --memory 2G --disk 10G
multipass shell wikijs-test
```

### 2. Clone and Setup

```bash
# Inside the multipass instance
git clone https://github.com/robertvigil/wikijs-secure-assets.git
cd wikijs-secure-assets

# Run automated setup - installs:
# - Node.js 20.x
# - Nginx
# - Creates mock auth service
# - Sets up test files and directories
./tests/setup-test-environment.sh
```

The setup script automatically installs all prerequisites. No manual installation needed!

**Note:** To open a second terminal in the same Multipass instance:
```bash
# From your local machine (in a new terminal)
multipass shell wikijs-test
```

### 3. Start Mock Auth Service

```bash
# Option 1: Background with nohup (recommended)
nohup node ~/test-assets/mock-auth-service.js > ~/test-assets/auth.log 2>&1 &

# Option 2: Run in foreground (open another terminal to run tests)
node ~/test-assets/mock-auth-service.js

# Check it's running
curl http://localhost:3002/health
```

### 4. Run Interactive Test Suite

```bash
# Step through all 10 test scenarios
./tests/manual-test-suite.sh
```

This walks you through each scenario, showing the full asset path and pausing between tests for review.

### 5. Cleanup

```bash
# Stop auth service
pkill -f mock-auth-service

# Stop nginx (optional)
sudo systemctl stop nginx

# Exit multipass
exit

# Delete instance (from your local machine)
multipass delete wikijs-test
multipass purge
```

## Production Verification

Verify production server before and after deployment.

### Prerequisites Check

```bash
# Set server connection
export WIKI_SERVER=user@yourdomain.com

# Run verification
./verify-production-server.sh
```

This checks:
- ✅ SSH connection
- ✅ Database access (Wiki.js PostgreSQL)
- ✅ Node.js and Nginx installation
- ✅ Port 3002 availability
- ✅ Disk space
- ✅ Asset-auth service status (if installed)
- ✅ JWT security (spoofed token rejection)

### Post-Deployment Verification

After running `./setup_secure_assets.sh`, run the verification again:

```bash
./verify-production-server.sh
```

All checks should pass, including:
- Asset-auth service running
- JWT signature verification enabled
- Spoofed JWT correctly rejected (HTTP 403)

## Manual Test Suite

The interactive test suite (`manual-test-suite.sh`) covers 10 scenarios:

### Test Scenarios

1. **Public Access (No Auth)** - Public assets accessible to everyone
2. **No Authentication** - Secure assets blocked without JWT
3. **JWT Security - Spoofed Token** - Invalid signature rejected (security critical)
4. **JWT Security - Wrong Secret** - Token signed with wrong secret rejected (security critical)
5. **User in Correct Group** - Member can access their group's assets
6. **User in Wrong Group** - Non-member blocked from group assets
7. **Multi-Group Membership** - User in multiple groups can access all
8. **Administrator Full Access** - Admin can access any folder
9. **Nested Folders** - Deep paths work (e.g., `/secure/developers/project1/diagram.txt`)
10. **Guest User (No Groups)** - User with no groups blocked from all secure assets

### Test Users (Mock Environment)

| User     | Email              | Groups                        |
|----------|--------------------|------------------------------ |
| admin    | admin@test.com     | Administrators (full access)  |
| manager  | manager@test.com   | managers                      |
| dev      | dev@test.com       | developers, managers          |
| finance  | finance@test.com   | finance                       |
| guest    | guest@test.com     | (no groups)                   |

### Quick Manual Tests

**Test 1: Public Access**
```bash
curl http://localhost:8080/public-assets/test.txt
# Expected: 200 OK, file contents
```

**Test 2: No Authentication**
```bash
curl http://localhost:8080/secure-assets/managers/report.txt
# Expected: 403 Forbidden
```

**Test 3: With Authentication**
```bash
# Generate token for developer user
TOKEN=$(~/test-assets/generate-token.js dev)

# Access developers folder (should work)
curl -H "Cookie: jwt=$TOKEN" http://localhost:8080/secure-assets/developers/project1/diagram.txt
# Expected: 200 OK, file contents

# Access finance folder (should fail - not in group)
curl -H "Cookie: jwt=$TOKEN" http://localhost:8080/secure-assets/finance/budget.txt
# Expected: 403 Forbidden
```

**Test 4: Administrator Access**
```bash
TOKEN=$(~/test-assets/generate-token.js admin)

# Admin can access ANY folder
curl -H "Cookie: jwt=$TOKEN" http://localhost:8080/secure-assets/managers/report.txt
curl -H "Cookie: jwt=$TOKEN" http://localhost:8080/secure-assets/developers/project1/diagram.txt
curl -H "Cookie: jwt=$TOKEN" http://localhost:8080/secure-assets/finance/budget.txt
# Expected: All return 200 OK
```

### View Auth Service Logs

```bash
# If using nohup
tail -f ~/test-assets/auth.log

# Example log output:
#   [timestamp] AUTH REQUEST:
#     Group: managers
#     Asset: report.txt
#     User: manager@test.com
#     Groups: ["managers"]
#     Result: ✅ ALLOWED (in group "managers")
```

## How Mock Testing Works

### No Database Required

The mock auth service reads group membership directly from JWT claims instead of querying a database.

**JWT Payload:**
```json
{
  "email": "dev@test.com",
  "groups": ["developers", "managers"],
  "iat": 1234567890,
  "exp": 1234571490
}
```

**Auth Logic:**
1. Extract JWT from cookie
2. Verify signature
3. Check if `groups` array contains required group OR "Administrators"
4. Return 200 (allowed) or 403 (denied)

### Test Environment

- **Auth Service:** Node.js Express on port 3002
- **Web Server:** Nginx on port 8080
- **Test Files:** `~/test-assets/public-assets/` and `~/test-assets/secure-assets/`

## Troubleshooting

### Auth service won't start

```bash
# Check if port 3002 is in use
sudo lsof -i :3002

# Kill existing process
pkill -f mock-auth-service
```

### Nginx errors

```bash
# Test configuration
sudo nginx -t

# Check logs
sudo tail -f /var/log/nginx/error.log
```

### Tests failing

```bash
# Verify services are running
curl http://localhost:3002/health  # Should return "OK"
curl http://localhost:8080         # Should return nginx default or 404

# Check auth service logs (run it without & to see output)
node ~/test-assets/mock-auth-service.js
```

### Production verification fails

```bash
# Check SSH connection
ssh user@yourdomain.com

# Verify Wiki.js database
PGPASSWORD='wikijspassword' psql -U wikijs -h localhost -d wikijs -c "SELECT COUNT(*) FROM users;"

# Check asset-auth service
sudo systemctl status asset-auth
sudo journalctl -u asset-auth -n 50
```

## Scripts Reference

- **`setup-test-environment.sh`** - Sets up local mock testing environment
- **`manual-test-suite.sh`** - Interactive test suite with 8 scenarios
- **`../verify-production-server.sh`** - Production server verification (in repo root)
- **`../production-config.example.sh`** - Example production config (in repo root)

## Next Steps

After successful testing:

1. **Local Testing** → Verify all scenarios pass
2. **Production Verification** → Check server prerequisites
3. **Deploy** → Run `./setup_secure_assets.sh`
4. **Post-Deploy Verification** → Confirm JWT security working

See **[../README.md](../README.md)** for production deployment guide.

---

**Last Updated:** November 25, 2025
