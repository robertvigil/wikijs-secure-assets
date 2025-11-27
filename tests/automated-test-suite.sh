#!/bin/bash

# Automated Test Suite - Non-interactive version
# Runs all tests and reports results at the end

set +e  # Don't exit on failures, we want to count them

PASSED=0
FAILED=0
TOTAL=0

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "  Automated Test Suite"
echo "=========================================="
echo ""

# Check if auth service is running
if ! curl -s http://localhost:3002/health >/dev/null 2>&1; then
    echo -e "${RED}❌ Auth service not running${NC}"
    echo "Start it with: nohup node ~/test-assets/mock-auth-service.js > ~/test-assets/auth.log 2>&1 &"
    exit 1
fi

echo -e "${GREEN}✓ Auth service is running${NC}"
echo ""

# Helper function to run a test
run_test() {
    local test_name="$1"
    local command="$2"
    local expected="$3"
    local check_type="${4:-contains}"  # "contains" or "equals"

    TOTAL=$((TOTAL + 1))
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "TEST $TOTAL: $test_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    result=$(eval "$command" 2>&1)

    echo "Command: $command"
    echo "Result: $result"
    echo "Expected: $expected"

    if [ "$check_type" = "equals" ]; then
        if [ "$result" = "$expected" ]; then
            echo -e "${GREEN}✓ PASS${NC}"
            PASSED=$((PASSED + 1))
        else
            echo -e "${RED}✗ FAIL${NC}"
            FAILED=$((FAILED + 1))
        fi
    else  # contains
        if [[ "$result" == *"$expected"* ]]; then
            echo -e "${GREEN}✓ PASS${NC}"
            PASSED=$((PASSED + 1))
        else
            echo -e "${RED}✗ FAIL${NC}"
            FAILED=$((FAILED + 1))
        fi
    fi
    echo ""
}

# Test 1: Public Access
run_test "Public Access (No Auth)" \
    "curl -s http://localhost:8080/public-assets/test.txt" \
    "Public file - anyone can access" \
    "contains"

# Test 2: No Auth - Should Block
run_test "No Authentication (Should Block)" \
    "curl -s http://localhost:8080/secure-assets/managers/report.txt" \
    "Access Denied" \
    "contains"

# Test 3: Spoofed JWT
HEADER="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
PAYLOAD="eyJlbWFpbCI6ImFkbWluQGZha2UuY29tIiwiZ3JvdXBzIjpbIm1hbmFnZXJzIiwiQWRtaW5pc3RyYXRvcnMiXX0"
FAKE_SIGNATURE="INVALID_SIGNATURE_SHOULD_BE_REJECTED"
SPOOFED_JWT="${HEADER}.${PAYLOAD}.${FAKE_SIGNATURE}"

run_test "JWT Security - Spoofed Token (Should Block)" \
    "curl -s -H 'Cookie: jwt=$SPOOFED_JWT' http://localhost:8080/secure-assets/managers/report.txt" \
    "Access Denied" \
    "contains"

# Test 4: JWT with Wrong Secret
WRONG_SECRET_JWT=$(node -e "
const jwt = require('jsonwebtoken');
const token = jwt.sign(
  { email: 'attacker@fake.com', groups: ['managers', 'Administrators'] },
  'wrong-secret-key-not-the-real-one',
  { algorithm: 'HS256' }
);
console.log(token);
" 2>/dev/null)

run_test "JWT Security - Wrong Secret (Should Block)" \
    "curl -s -H 'Cookie: jwt=$WRONG_SECRET_JWT' http://localhost:8080/secure-assets/managers/report.txt" \
    "Access Denied" \
    "contains"

# Test 5: User in Correct Group
TOKEN=$(~/test-assets/generate-token.js manager)
run_test "User in Correct Group (Should Allow)" \
    "curl -s -H 'Cookie: jwt=$TOKEN' http://localhost:8080/secure-assets/managers/report.txt" \
    "Managers only" \
    "equals"

# Test 6: User in Wrong Group
TOKEN=$(~/test-assets/generate-token.js manager)
run_test "User in Wrong Group (Should Block)" \
    "curl -s -H 'Cookie: jwt=$TOKEN' http://localhost:8080/secure-assets/developers/project1/diagram.txt" \
    "Access Denied" \
    "equals"

# Test 7a: Multi-Group - developers asset
TOKEN=$(~/test-assets/generate-token.js dev)
run_test "Multi-Group: Developer Asset Access" \
    "curl -s -H 'Cookie: jwt=$TOKEN' http://localhost:8080/secure-assets/developers/project1/diagram.txt" \
    "Developers only (nested)" \
    "equals"

# Test 7b: Multi-Group - managers asset
TOKEN=$(~/test-assets/generate-token.js dev)
run_test "Multi-Group: Manager Asset Access" \
    "curl -s -H 'Cookie: jwt=$TOKEN' http://localhost:8080/secure-assets/managers/report.txt" \
    "Managers only" \
    "equals"

# Test 7c: Multi-Group - wrong group
TOKEN=$(~/test-assets/generate-token.js dev)
run_test "Multi-Group: Wrong Group (Should Block)" \
    "curl -s -H 'Cookie: jwt=$TOKEN' http://localhost:8080/secure-assets/finance/budget.txt" \
    "Access Denied" \
    "equals"

# Test 8a: Admin - managers
TOKEN=$(~/test-assets/generate-token.js admin)
run_test "Administrator: Managers Access" \
    "curl -s -H 'Cookie: jwt=$TOKEN' http://localhost:8080/secure-assets/managers/report.txt" \
    "Managers only" \
    "equals"

# Test 8b: Admin - developers
TOKEN=$(~/test-assets/generate-token.js admin)
run_test "Administrator: Developers Access" \
    "curl -s -H 'Cookie: jwt=$TOKEN' http://localhost:8080/secure-assets/developers/project1/diagram.txt" \
    "Developers only (nested)" \
    "equals"

# Test 8c: Admin - finance
TOKEN=$(~/test-assets/generate-token.js admin)
run_test "Administrator: Finance Access" \
    "curl -s -H 'Cookie: jwt=$TOKEN' http://localhost:8080/secure-assets/finance/budget.txt" \
    "Finance only" \
    "equals"

# Test 9: Nested Folders
TOKEN=$(~/test-assets/generate-token.js dev)
run_test "Nested Folders Work Correctly" \
    "curl -s -H 'Cookie: jwt=$TOKEN' http://localhost:8080/secure-assets/developers/project1/diagram.txt" \
    "Developers only (nested)" \
    "equals"

# Test 10: Guest User (No Groups)
TOKEN=$(~/test-assets/generate-token.js guest)
run_test "Guest User (No Groups - Should Block)" \
    "curl -s -H 'Cookie: jwt=$TOKEN' http://localhost:8080/secure-assets/managers/report.txt" \
    "Access Denied" \
    "equals"

# Summary
echo "=========================================="
echo "  Test Summary"
echo "=========================================="
echo ""
echo "Total Tests:  $TOTAL"
echo -e "Passed:       ${GREEN}$PASSED${NC}"
echo -e "Failed:       ${RED}$FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ ALL TESTS PASSED!${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}✗ SOME TESTS FAILED${NC}"
    echo ""
    exit 1
fi
