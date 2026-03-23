#!/bin/bash
# ============================================================================
# lib-test.sh - Shared test helpers for test-stack.sh and test-connectivity.sh
# ============================================================================
# Usage: source "$(dirname "$0")/lib-test.sh"
# ============================================================================

# Resolve paths
TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_PROJECT_ROOT="$(cd "$TEST_SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[PASS]${NC}  $*"; }
warning() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail_msg(){ echo -e "${RED}[FAIL]${NC}  $*"; }
section() { echo -e "\n${CYAN}══ $* ══${NC}"; }

# Test counters
PASSED=0; FAILED=0

pass() { PASSED=$((PASSED+1)); success "$1"; }
fail() { FAILED=$((FAILED+1)); fail_msg "$1"; }

# ─── Test helpers ────────────────────────────────────────────────────────────

# test_endpoint <label> <expected_http_code> <curl_args...>
test_endpoint() {
    local label=$1 expected=$2
    shift 2
    local actual
    actual=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 "$@")
    if [[ "$actual" == "$expected" ]]; then
        pass "[$label] HTTP $actual"
    else
        fail "[$label] HTTP $actual (expected $expected)"
        curl -sk --max-time 5 "$@" 2>/dev/null | head -3 || true
    fi
}

# gen_token <partner-id>
gen_token() {
    bash "$TEST_SCRIPT_DIR/generate-jwt.sh" "$1" 3600 2>/dev/null
}

# login and return access token
# Usage: TOKEN=$(get_auth_token "$BASE" "admin" "admin123")
get_auth_token() {
    local base=$1 username=$2 password=$3
    curl -sk "${base}/api/auth/login" \
        -H 'Content-Type: application/json' \
        -d "{\"username\":\"${username}\",\"password\":\"${password}\"}" \
        | python3 -c "import sys,json; print(json.load(sys.stdin).get('accessToken',''))" 2>/dev/null
}

# ─── Summary ─────────────────────────────────────────────────────────────────

print_summary() {
    section "Test Summary"
    echo -e "  ${GREEN}PASSED${NC}: $PASSED"
    echo -e "  ${RED}FAILED${NC}: $FAILED"
    echo ""
    if [[ $FAILED -eq 0 ]]; then
        success "All tests passed!"
    else
        fail_msg "$FAILED test(s) failed"
    fi
}
