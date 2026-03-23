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
    actual=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 3 "$@")
    if [[ "$actual" == "$expected" ]]; then
        pass "[$label] HTTP $actual"
    else
        fail "[$label] HTTP $actual (expected $expected)"
        curl -sk --max-time 2 "$@" 2>/dev/null | head -3 || true
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

# ─── Readiness ───────────────────────────────────────────────────────────────

# wait_for_services <timeout_seconds> <service_names...>
# Polls container logs for Spring Boot "Started" message every 2s.
# (Podman on macOS does not propagate Dockerfile HEALTHCHECK to containers
#  started via `podman run`, so we cannot use `podman inspect` health status.)
wait_for_services() {
    local timeout=$1; shift
    local services=("$@")
    local ready=0
    local elapsed=0
    local total=${#services[@]}

    info "Waiting for $total services to become ready (${timeout}s timeout) ..."
    while [[ $elapsed -lt $timeout ]]; do
        ready=0
        for svc in "${services[@]}"; do
            podman logs "$svc" 2>&1 | grep -q "Started.*Application" && ready=$((ready + 1))
        done
        if [[ $ready -ge $total ]]; then
            success "All $total services ready (${elapsed}s)"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
        [[ $((elapsed % 10)) -eq 0 ]] && info "  $ready/$total ready (${elapsed}s) ..."
    done

    fail_msg "Only $ready/$total services ready after ${timeout}s"
    for svc in "${services[@]}"; do
        podman logs "$svc" 2>&1 | grep -q "Started.*Application" || warning "  $svc: not ready"
    done
    return 1
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
