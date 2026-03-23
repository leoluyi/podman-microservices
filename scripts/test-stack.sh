#!/bin/bash
# ============================================================================
# test-stack.sh - Self-contained e2e test orchestration
# ============================================================================
# Starts the full stack via local-start.sh on dedicated test ports (9443/9080),
# runs all test suites, and cleans up on exit. Safe to run alongside a dev stack.
#
# Test Suites:
#   T1: Infrastructure   - PostgreSQL, Flyway migrations, service health gates
#   T2: Auth             - Login, register, token-protected access, bad creds
#   T3: Order CRUD       - Create, list, get, stats, update status, delete
#   T4: Partner Perms    - 3-tier permission matrix (A=full, B=read+create, C=read)
#   T5: SSL + Frontend   - HTTPS health, HTTP redirect, security headers, SPA
#
# Usage: ./scripts/test-stack.sh [--skip-build]
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib-test.sh"

# ─── Configuration ───────────────────────────────────────────────────────────
# Use dedicated ports to avoid collision with dev stack on 8443/8080
export HTTPS_PORT=9443
export HTTP_PORT=9080

BASE="https://localhost:${HTTPS_PORT}"
SKIP_BUILD=false

for arg in "$@"; do
    [[ "$arg" == "--skip-build" ]] && SKIP_BUILD=true
done

# ─── Cleanup ─────────────────────────────────────────────────────────────────
cleanup() {
    section "Cleanup"
    info "Stopping test stack ..."
    HTTPS_PORT=$HTTPS_PORT HTTP_PORT=$HTTP_PORT "$SCRIPT_DIR/local-stop.sh" --clean 2>&1 | tail -3
    info "Cleanup complete"
}
trap cleanup EXIT

# ─── Start Stack ─────────────────────────────────────────────────────────────
section "Starting Test Stack (ports $HTTPS_PORT/$HTTP_PORT)"

local_start_args=()
if [[ "$SKIP_BUILD" == true ]]; then
    local_start_args+=(--skip-build)
fi

"$SCRIPT_DIR/local-start.sh" "${local_start_args[@]}" 2>&1 | grep -E "(SUCCESS|ERROR|Building|started|is up|Skipping)"

# Wait for all Spring Boot services to be healthy via Podman healthcheck
wait_for_services 120 api-auth-1 api-order-1 api-user-1 api-product-1 bff-1

# ─── T1: Infrastructure ─────────────────────────────────────────────────────
run_T1_infra() {
    section "T1: Infrastructure"

    # PostgreSQL
    if podman exec postgres pg_isready -U postgres -q 2>/dev/null; then
        pass "[postgres] pg_isready"
    else
        fail "[postgres] pg_isready"
    fi

    # Table count (should have 8: users, roles, permissions, user_roles, role_permissions, orders, 2x flyway)
    local count
    count=$(podman exec postgres psql -U app_user -d microservices_dev -tAc \
        "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'" 2>/dev/null)
    if [[ "$count" -ge 8 ]]; then
        pass "[postgres] $count tables in microservices_dev"
    else
        fail "[postgres] only $count tables (expected >= 8)"
    fi

    # Flyway schema history table exists (proves Flyway ran at some point)
    local flyway_tables
    flyway_tables=$(podman exec postgres psql -U app_user -d microservices_dev -tAc \
        "SELECT count(*) FROM information_schema.tables WHERE table_name LIKE 'flyway_%'" 2>/dev/null)
    if [[ "$flyway_tables" -ge 2 ]]; then
        pass "[flyway] $flyway_tables history tables exist"
    else
        fail "[flyway] expected >= 2 history tables, got $flyway_tables"
    fi

    pass "[services] all 5 Spring Boot services healthy (verified at startup)"
}

# ─── T2: Auth ────────────────────────────────────────────────────────────────
run_T2_auth() {
    section "T2: Auth"

    # Login with valid credentials
    local login_resp
    login_resp=$(curl -sk "${BASE}/api/auth/login" \
        -H 'Content-Type: application/json' \
        -d '{"username":"admin","password":"admin123"}')
    if echo "$login_resp" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['accessToken']" 2>/dev/null; then
        pass "[login] admin/admin123 -> accessToken returned"
    else
        fail "[login] admin/admin123 -> no accessToken"
    fi

    # Login with bad credentials
    test_endpoint "login bad creds" 400 \
        "${BASE}/api/auth/login" \
        -H 'Content-Type: application/json' \
        -d '{"username":"admin","password":"wrongpassword"}'

    # Register new user (unique name per run)
    local ts
    ts=$(date +%s)
    test_endpoint "register new user" 201 \
        "${BASE}/api/auth/register" \
        -H 'Content-Type: application/json' \
        -d "{\"username\":\"testuser_${ts}\",\"password\":\"testpass123\",\"email\":\"t2_${ts}@example.com\"}"

    # Token protects endpoints
    local token
    token=$(get_auth_token "$BASE" "admin" "admin123")
    test_endpoint "GET /api/orders with token" 200 \
        -H "Authorization: Bearer $token" "${BASE}/api/orders"
    test_endpoint "GET /api/orders no token" 401 "${BASE}/api/orders"
}

# ─── T3: Order CRUD ──────────────────────────────────────────────────────────
run_T3_orders() {
    section "T3: Order CRUD"

    local token
    token=$(get_auth_token "$BASE" "admin" "admin123")
    local auth=(-H "Authorization: Bearer $token")

    # Create
    local create_resp
    create_resp=$(curl -sk -w "\n%{http_code}" "${BASE}/api/orders" \
        "${auth[@]}" -H 'Content-Type: application/json' \
        -d '{"customerName":"Test Customer","totalAmount":99.99}')
    local create_code
    create_code=$(echo "$create_resp" | tail -1)
    local create_body
    create_body=$(echo "$create_resp" | sed '$d')
    if [[ "$create_code" == "201" ]]; then
        pass "[create order] HTTP 201"
    else
        fail "[create order] HTTP $create_code (expected 201)"
    fi

    local order_id
    order_id=$(echo "$create_body" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null)

    # Create second order for stats
    curl -sk -o /dev/null "${BASE}/api/orders" \
        "${auth[@]}" -H 'Content-Type: application/json' \
        -d '{"customerName":"Another Customer","totalAmount":50.00}'

    # List
    test_endpoint "list orders" 200 "${auth[@]}" "${BASE}/api/orders"

    # Get by ID
    test_endpoint "get order $order_id" 200 "${auth[@]}" "${BASE}/api/orders/${order_id}"

    # Stats
    test_endpoint "order stats" 200 "${auth[@]}" "${BASE}/api/orders/stats"

    # Update status
    test_endpoint "update status" 200 \
        -X PATCH "${auth[@]}" -H 'Content-Type: application/json' \
        -d '{"status":"COMPLETED"}' "${BASE}/api/orders/${order_id}/status"

    # Delete
    test_endpoint "delete order" 204 \
        -X DELETE "${auth[@]}" "${BASE}/api/orders/${order_id}"
}

# ─── T4: Partner Permissions ─────────────────────────────────────────────────
run_T4_partner() {
    section "T4: Partner API Permission Matrix"

    local TOKEN_A TOKEN_B TOKEN_C
    TOKEN_A=$(gen_token partner-company-a)
    TOKEN_B=$(gen_token partner-company-b)
    TOKEN_C=$(gen_token partner-company-c)

    local partner_base="${BASE}/partner/api/order"

    # Seed an order via Partner A for subsequent tests
    local seed_resp
    seed_resp=$(curl -sk "${partner_base}/orders" \
        -H "Authorization: Bearer $TOKEN_A" \
        -H 'Content-Type: application/json' \
        -d '{"customerName":"Partner Seed","totalAmount":100.00}')
    local seed_id
    seed_id=$(echo "$seed_resp" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null || echo "1")

    # ── Partner A: Full CRUD ──
    info "Partner A (full CRUD) ..."
    test_endpoint "A: GET /orders" 200 \
        -H "Authorization: Bearer $TOKEN_A" "${partner_base}/orders"
    test_endpoint "A: POST /orders" 201 \
        -H "Authorization: Bearer $TOKEN_A" -H 'Content-Type: application/json' \
        -d '{"customerName":"A Order","totalAmount":10.00}' "${partner_base}/orders"
    test_endpoint "A: GET /orders/${seed_id}" 200 \
        -H "Authorization: Bearer $TOKEN_A" "${partner_base}/orders/${seed_id}"
    test_endpoint "A: GET /orders/stats" 200 \
        -H "Authorization: Bearer $TOKEN_A" "${partner_base}/orders/stats"
    test_endpoint "A: PATCH /orders/${seed_id}/status" 200 \
        -X PATCH -H "Authorization: Bearer $TOKEN_A" -H 'Content-Type: application/json' \
        -d '{"status":"SHIPPED"}' "${partner_base}/orders/${seed_id}/status"

    # Create a disposable order for delete test
    local del_resp
    del_resp=$(curl -sk "${partner_base}/orders" \
        -H "Authorization: Bearer $TOKEN_A" -H 'Content-Type: application/json' \
        -d '{"customerName":"Delete Me","totalAmount":1.00}')
    local del_id
    del_id=$(echo "$del_resp" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null || echo "999")
    test_endpoint "A: DELETE /orders/${del_id}" 204 \
        -X DELETE -H "Authorization: Bearer $TOKEN_A" "${partner_base}/orders/${del_id}"

    # ── Partner B: Read + Create (no update, no delete) ──
    info "Partner B (read + create) ..."
    test_endpoint "B: GET /orders" 200 \
        -H "Authorization: Bearer $TOKEN_B" "${partner_base}/orders"
    test_endpoint "B: POST /orders" 201 \
        -H "Authorization: Bearer $TOKEN_B" -H 'Content-Type: application/json' \
        -d '{"customerName":"B Order","totalAmount":5.00}' "${partner_base}/orders"
    test_endpoint "B: DELETE (denied)" 403 \
        -X DELETE -H "Authorization: Bearer $TOKEN_B" "${partner_base}/orders/${seed_id}"
    test_endpoint "B: PATCH (denied)" 403 \
        -X PATCH -H "Authorization: Bearer $TOKEN_B" -H 'Content-Type: application/json' \
        -d '{"status":"X"}' "${partner_base}/orders/${seed_id}/status"

    # ── Partner C: Read only ──
    info "Partner C (read only) ..."
    test_endpoint "C: GET /orders" 200 \
        -H "Authorization: Bearer $TOKEN_C" "${partner_base}/orders"
    test_endpoint "C: POST (denied)" 403 \
        -H "Authorization: Bearer $TOKEN_C" -H 'Content-Type: application/json' \
        -d '{"customerName":"C Denied","totalAmount":1.00}' "${partner_base}/orders"

    # ── Edge cases ──
    info "Edge cases ..."
    test_endpoint "no token" 401 "${partner_base}/orders"
    test_endpoint "invalid token" 401 \
        -H "Authorization: Bearer invalid.token.here" "${partner_base}/orders"
}

# ─── T5: SSL/Security + Frontend ─────────────────────────────────────────────
run_T5_security() {
    section "T5: SSL/Security + Frontend"

    test_endpoint "HTTPS /health" 200 "${BASE}/health"
    test_endpoint "HTTP redirect" 301 "http://localhost:${HTTP_PORT}/"
    test_endpoint "frontend SPA" 200 "${BASE}/"

    # Security headers
    local headers
    headers=$(curl -sI -k "${BASE}/" 2>/dev/null)
    local missing=()
    for h in "strict-transport-security" "content-security-policy" "x-frame-options" "x-content-type-options" "x-xss-protection"; do
        if ! echo "$headers" | grep -qi "^${h}:"; then
            missing+=("$h")
        fi
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
        pass "[security headers] all 5 present"
    else
        fail "[security headers] missing: ${missing[*]}"
    fi
}

# ─── Main ────────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Podman Microservices - Test Stack   ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
    echo ""

    run_T1_infra
    run_T2_auth
    run_T3_orders
    run_T4_partner
    run_T5_security

    print_summary
    [[ $FAILED -eq 0 ]]
}

main "$@"
