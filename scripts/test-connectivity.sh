#!/bin/bash
# ============================================================================
# test-connectivity.sh - Quick smoke test against a running stack
# ============================================================================
# Runs against a stack already started by local-start.sh (ports 8443/8080).
# No builds, no container management. Finishes in < 5 seconds.
#
# Usage: ./scripts/test-connectivity.sh
# ============================================================================

set -euo pipefail

source "$(dirname "$0")/lib-test.sh"

HTTPS_PORT="${HTTPS_PORT:-8443}"
HTTP_PORT="${HTTP_PORT:-8080}"
BASE="https://localhost:${HTTPS_PORT}"

echo ""
echo "=========================================="
echo "  Connectivity Smoke Test (:${HTTPS_PORT})"
echo "=========================================="
echo ""

# ─── 1. SSL Proxy ────────────────────────────────────────────────────────────
section "SSL Proxy"
test_endpoint "HTTPS /health" 200 "${BASE}/health"
test_endpoint "HTTP redirect" 301 "http://localhost:${HTTP_PORT}/"

# ─── 2. Auth ─────────────────────────────────────────────────────────────────
section "Auth"
TOKEN=$(get_auth_token "$BASE" "admin" "admin123")
if [[ -n "$TOKEN" && "$TOKEN" != "None" ]]; then
    pass "[login] admin/admin123 -> token obtained"
else
    fail "[login] admin/admin123 -> no token"
    TOKEN=""
fi

if [[ -n "$TOKEN" ]]; then
    test_endpoint "protected endpoint with token" 200 \
        -H "Authorization: Bearer $TOKEN" "${BASE}/api/orders"
fi
test_endpoint "protected endpoint no token" 401 "${BASE}/api/orders"

# ─── 3. Order CRUD ───────────────────────────────────────────────────────────
section "Order CRUD"
if [[ -n "$TOKEN" ]]; then
    test_endpoint "create order" 201 \
        -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
        -d '{"customerName":"Smoke Test","totalAmount":1.00}' "${BASE}/api/orders"
    test_endpoint "list orders" 200 \
        -H "Authorization: Bearer $TOKEN" "${BASE}/api/orders"
fi

# ─── 4. Partner API ──────────────────────────────────────────────────────────
section "Partner API"
TOKEN_A=$(gen_token partner-company-a)
TOKEN_B=$(gen_token partner-company-b)
TOKEN_C=$(gen_token partner-company-c)

test_endpoint "A: GET orders" 200 \
    -H "Authorization: Bearer $TOKEN_A" "${BASE}/partner/api/order/orders"
test_endpoint "B: GET orders" 200 \
    -H "Authorization: Bearer $TOKEN_B" "${BASE}/partner/api/order/orders"
test_endpoint "B: DELETE (denied)" 403 \
    -X DELETE -H "Authorization: Bearer $TOKEN_B" "${BASE}/partner/api/order/orders/1"
test_endpoint "C: POST (denied)" 403 \
    -H "Authorization: Bearer $TOKEN_C" -H 'Content-Type: application/json' \
    -d '{"customerName":"X","totalAmount":1}' "${BASE}/partner/api/order/orders"
test_endpoint "no token" 401 "${BASE}/partner/api/order/orders"

# ─── 5. Security Headers ─────────────────────────────────────────────────────
section "Security Headers"
headers=$(curl -sI -k "${BASE}/" 2>/dev/null)
missing=()
for h in "strict-transport-security" "content-security-policy" "x-frame-options" "x-content-type-options" "x-xss-protection"; do
    echo "$headers" | grep -qi "^${h}:" || missing+=("$h")
done
if [[ ${#missing[@]} -eq 0 ]]; then
    pass "[security headers] all 5 present"
else
    fail "[security headers] missing: ${missing[*]}"
fi

# ─── 6. Frontend ─────────────────────────────────────────────────────────────
section "Frontend"
test_endpoint "frontend SPA" 200 "${BASE}/"

# ─── Summary ──────────────────────────────────────────────────────────────────
print_summary
[[ $FAILED -eq 0 ]]
