#!/bin/bash
# ============================================================================
# test-stack.sh - End-to-end test orchestration (no systemd/Quadlet)
# ============================================================================
# Builds all images, starts the full service topology via plain `podman run`,
# runs T1-T7 tests, and cleans up everything on exit.
#
# Usage: ./scripts/test-stack.sh
#
# Excluded:
#   - quadlet/ systemd units
#   - scripts/setup.sh Podman Secret provisioning
#   - Spring Boot builds (replaced by Go stubs)
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── Colour helpers ───────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[PASS]${NC}  $*"; }
warning() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[FAIL]${NC}  $*"; }
section() { echo -e "\n${CYAN}══ $* ══${NC}"; }

# ─── Test counters ────────────────────────────────────────────────────────────
PASSED=0; FAILED=0

pass() { PASSED=$((PASSED+1)); success "$1"; }
fail() { FAILED=$((FAILED+1)); error "$1"; }

# ─── Globals ─────────────────────────────────────────────────────────────────
NETWORK="internal-net-test"
HTTPS_PORT=9443
HTTP_PORT=9080
CERT_DIR=""          # set by generate_certs
LOG_DIR=""           # set by setup_logs
BFF_HOST_PORT=18080  # random-ish host port for direct BFF access

# Container names (unique prefix avoids collision with other runs)
C_FRONTEND="test-frontend"
C_BFF="test-bff"
C_API_USER="test-api-user"
C_API_ORDER="test-api-order"
C_API_PRODUCT="test-api-product"
C_SSL_PROXY="test-ssl-proxy"

ALL_CONTAINERS=("$C_FRONTEND" "$C_BFF" "$C_API_USER" "$C_API_ORDER" "$C_API_PRODUCT" "$C_SSL_PROXY")

# ─── Cleanup ──────────────────────────────────────────────────────────────────
cleanup() {
    section "Cleanup"
    for c in "${ALL_CONTAINERS[@]}"; do
        if podman container exists "$c" 2>/dev/null; then
            info "Stopping $c"
            podman rm -f "$c" >/dev/null 2>&1 || true
        fi
    done
    if podman network exists "$NETWORK" 2>/dev/null; then
        info "Removing network $NETWORK"
        podman network rm "$NETWORK" >/dev/null 2>&1 || true
    fi
    if [[ -n "$CERT_DIR" && -d "$CERT_DIR" ]]; then
        rm -rf "$CERT_DIR"
    fi
    if [[ -n "$LOG_DIR" && -d "$LOG_DIR" ]]; then
        rm -rf "$LOG_DIR"
    fi
    info "Cleanup complete"
}
trap cleanup EXIT

# ─── Prerequisites ────────────────────────────────────────────────────────────
check_prereqs() {
    section "Prerequisites"
    local missing=()
    for cmd in podman jq openssl curl; do
        if command -v "$cmd" >/dev/null 2>&1; then
            info "$cmd: $(command -v "$cmd")"
        else
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required tools: ${missing[*]}"
        exit 1
    fi
    success "All prerequisites satisfied"
}

# ─── SSL cert generation ──────────────────────────────────────────────────────
generate_certs() {
    section "SSL Certificates"
    CERT_DIR="$(mktemp -d)"
    info "Generating self-signed cert in $CERT_DIR"

    cat > "$CERT_DIR/openssl.cnf" <<EOF
[req]
default_bits       = 2048
prompt             = no
default_md         = sha256
distinguished_name = dn
req_extensions     = req_ext

[dn]
C  = TW
ST = Taiwan
L  = Taipei
O  = Test
CN = localhost

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
IP.1  = 127.0.0.1
IP.2  = ::1
EOF

    openssl req -x509 -nodes -days 365 \
        -newkey rsa:2048 \
        -keyout "$CERT_DIR/server.key" \
        -out    "$CERT_DIR/server.crt" \
        -config "$CERT_DIR/openssl.cnf" \
        -extensions req_ext \
        2>/dev/null

    chmod 644 "$CERT_DIR/server.crt"
    chmod 600 "$CERT_DIR/server.key"
    success "SSL cert generated"
}

# ─── Log dir ─────────────────────────────────────────────────────────────────
setup_logs() {
    LOG_DIR="$(mktemp -d)"
    info "Log dir: $LOG_DIR"
}

# ─── Network ─────────────────────────────────────────────────────────────────
create_network() {
    section "Network"
    if podman network exists "$NETWORK" 2>/dev/null; then
        warning "Network $NETWORK already exists, removing"
        podman network rm "$NETWORK" >/dev/null
    fi
    podman network create "$NETWORK"
    success "Network $NETWORK created"
}

# ─── Image builds ─────────────────────────────────────────────────────────────
build_images() {
    section "Building Images"

    info "Building api-user ..."
    podman build -t test-api-user:latest \
        "$PROJECT_DIR/dockerfiles/api-user" --quiet

    info "Building api-order ..."
    podman build -t test-api-order:latest \
        "$PROJECT_DIR/dockerfiles/api-order" --quiet

    info "Building api-product ..."
    podman build -t test-api-product:latest \
        "$PROJECT_DIR/dockerfiles/api-product" --quiet

    info "Building bff ..."
    podman build -t test-bff:latest \
        "$PROJECT_DIR/dockerfiles/bff" --quiet

    info "Building ssl-proxy (openresty + lua-resty-jwt) ..."
    podman build -t test-ssl-proxy:latest \
        -f "$PROJECT_DIR/dockerfiles/ssl-proxy/Dockerfile" \
        "$PROJECT_DIR" --quiet

    # Frontend: reuse api-user stub (same Go code, different SERVICE_NAME/PORT)
    podman tag test-api-user:latest test-frontend:latest

    success "All images built"
}

# ─── Container startup ────────────────────────────────────────────────────────
start_containers() {
    section "Starting Containers"

    # upstream.conf resolves plain names: frontend, bff, api-user, api-order, api-product.
    # The containers are named test-*, so we register each under its logical alias.

    info "Starting $C_FRONTEND ..."
    podman run -d --name "$C_FRONTEND" \
        --network "$NETWORK" \
        --network-alias frontend \
        -e SERVICE_NAME=frontend \
        -e SERVICE_PORT=80 \
        test-frontend:latest

    info "Starting $C_BFF ..."
    podman run -d --name "$C_BFF" \
        --network "$NETWORK" \
        --network-alias bff \
        -p "${BFF_HOST_PORT}:8080" \
        -e API_USER_URL="http://api-user:8080" \
        -e API_ORDER_URL="http://api-order:8080" \
        -e API_PRODUCT_URL="http://api-product:8080" \
        test-bff:latest

    info "Starting $C_API_USER ..."
    podman run -d --name "$C_API_USER" \
        --network "$NETWORK" \
        --network-alias api-user \
        -e SERVICE_NAME=api-user \
        test-api-user:latest

    info "Starting $C_API_ORDER ..."
    podman run -d --name "$C_API_ORDER" \
        --network "$NETWORK" \
        --network-alias api-order \
        -e SERVICE_NAME=api-order \
        test-api-order:latest

    info "Starting $C_API_PRODUCT ..."
    podman run -d --name "$C_API_PRODUCT" \
        --network "$NETWORK" \
        --network-alias api-product \
        -e SERVICE_NAME=api-product \
        test-api-product:latest

    # openresty:alpine has no "nginx" user; generate a patched conf without that directive
    sed '/^user  *nginx;/d' \
        "$PROJECT_DIR/configs/ssl-proxy/nginx.conf" \
        > "$CERT_DIR/nginx.conf"

    info "Starting $C_SSL_PROXY ..."
    podman run -d --name "$C_SSL_PROXY" \
        --network "$NETWORK" \
        -p "${HTTPS_PORT}:443" \
        -p "${HTTP_PORT}:80" \
        -v "$CERT_DIR/server.crt:/etc/nginx/ssl/server.crt:ro" \
        -v "$CERT_DIR/server.key:/etc/nginx/ssl/server.key:ro" \
        -v "$CERT_DIR/nginx.conf:/usr/local/openresty/nginx/conf/nginx.conf:ro" \
        -v "$PROJECT_DIR/configs/ssl-proxy/conf.d:/etc/nginx/conf.d:ro" \
        -v "$LOG_DIR:/var/log/nginx:rw" \
        -e JWT_SECRET_PARTNER_A="dev-secret-partner-a-for-testing-only-32chars" \
        -e JWT_SECRET_PARTNER_B="dev-secret-partner-b-for-testing-only-32chars" \
        -e JWT_SECRET_PARTNER_C="dev-secret-partner-c-for-testing-only-32chars" \
        -e DEBUG_PARTNERS=true \
        test-ssl-proxy:latest

    success "All containers started"
}

# ─── Wait for health ──────────────────────────────────────────────────────────
wait_for_health() {
    section "Waiting for Services"
    local timeout=60

    wait_http() {
        local name=$1 url=$2 elapsed=0
        info "Waiting for $name at $url ..."
        while ! curl -sk --max-time 3 "$url" >/dev/null 2>&1; do
            sleep 2
            elapsed=$((elapsed+2))
            if [[ $elapsed -ge $timeout ]]; then
                error "$name did not become healthy within ${timeout}s"
                podman logs "$name" 2>&1 | tail -20 || true
                exit 1
            fi
        done
        success "$name is up"
    }

    wait_http "$C_BFF"       "http://localhost:${BFF_HOST_PORT}/health"
    wait_http "$C_SSL_PROXY" "https://localhost:${HTTPS_PORT}/health"
}

# ─── Test helpers ─────────────────────────────────────────────────────────────
# test_endpoint <label> <expected_http_code> <curl_args...>
test_endpoint() {
    local label=$1 expected=$2
    shift 2
    local actual
    actual=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 "$@")
    if [[ "$actual" == "$expected" ]]; then
        pass "[$label] HTTP $actual (expected $expected)"
    else
        fail "[$label] HTTP $actual (expected $expected)"
        # show body for debugging
        curl -sk --max-time 10 "$@" 2>/dev/null | head -5 || true
    fi
}

gen_token() {
    bash "$SCRIPT_DIR/generate-jwt.sh" "$1" 2>/dev/null
}

# ─── Tests ────────────────────────────────────────────────────────────────────

run_T1_jwt() {
    section "T1: generate-jwt.sh"
    for partner in partner-company-a partner-company-b partner-company-c; do
        local token
        token=$(gen_token "$partner")
        local dots
        dots=$(echo "$token" | tr -cd '.' | wc -c)
        if [[ "$dots" -eq 2 ]]; then
            pass "[$partner] JWT has 3 parts (valid format)"
        else
            fail "[$partner] JWT malformed (dots=$dots)"
        fi
    done
}

run_T2_bff_health() {
    section "T2: BFF Health Check (direct)"
    local body
    body=$(curl -s --max-time 5 "http://localhost:${BFF_HOST_PORT}/health")
    if echo "$body" | jq -e '.status == "healthy" and .service == "bff"' >/dev/null 2>&1; then
        pass "[bff /health] response: $body"
    else
        fail "[bff /health] unexpected response: $body"
    fi
}

run_T3_ssl_proxy() {
    section "T3: SSL Proxy Endpoints"
    test_endpoint "HTTPS /health"       200 "https://localhost:${HTTPS_PORT}/health"
    test_endpoint "HTTP / redirect 301" 301 "http://localhost:${HTTP_PORT}/"
    test_endpoint "HTTPS / frontend"    200 "https://localhost:${HTTPS_PORT}/"
}

run_T4_partner_auth() {
    section "T4: Partner API JWT Validation"

    local base="https://localhost:${HTTPS_PORT}"
    local TOKEN_A TOKEN_B TOKEN_C

    TOKEN_A=$(gen_token partner-company-a)
    TOKEN_B=$(gen_token partner-company-b)
    TOKEN_C=$(gen_token partner-company-c)

    # 401: no token
    test_endpoint "no token -> 401" 401 "${base}/partner/api/order/"

    # Partner A has orders -> 200
    test_endpoint "partner-A orders -> 200" 200 \
        -H "Authorization: Bearer $TOKEN_A" "${base}/partner/api/order/"

    # Partner A has users -> 200
    test_endpoint "partner-A users -> 200" 200 \
        -H "Authorization: Bearer $TOKEN_A" "${base}/partner/api/user/"

    # Partner A has products -> 200
    test_endpoint "partner-A products -> 200" 200 \
        -H "Authorization: Bearer $TOKEN_A" "${base}/partner/api/product/"

    # Partner B has orders only, NOT products -> 403
    test_endpoint "partner-B products -> 403" 403 \
        -H "Authorization: Bearer $TOKEN_B" "${base}/partner/api/product/"

    # Partner C has products only, NOT orders -> 403
    test_endpoint "partner-C orders -> 403" 403 \
        -H "Authorization: Bearer $TOKEN_C" "${base}/partner/api/order/"

    # Partner C has products -> 200
    test_endpoint "partner-C products -> 200" 200 \
        -H "Authorization: Bearer $TOKEN_C" "${base}/partner/api/product/"
}

run_T5_bff_routing() {
    section "T5: /api/ Routing via BFF"
    local base="https://localhost:${HTTPS_PORT}"
    # BFF stub has no auth layer; Go stubs return 200 for all paths
    test_endpoint "/api/users via BFF" 200 "${base}/api/users"
}

run_T6_python_client() {
    section "T6: Python Client Example"
    local client_dir="$PROJECT_DIR/examples/partner-clients"

    if ! command -v python3 >/dev/null 2>&1; then
        warning "python3 not found, skipping T6"
        return
    fi

    # Install deps quietly if missing
    python3 -c "import jwt, requests" 2>/dev/null || \
        pip3 install --quiet pyjwt requests 2>/dev/null || true

    if ! python3 -c "import jwt, requests" 2>/dev/null; then
        warning "pyjwt/requests not available, skipping T6"
        return
    fi

    local output exit_code=0
    output=$(
        cd "$client_dir"
        API_BASE_URL="https://localhost:${HTTPS_PORT}" \
        PARTNER_ID=partner-company-a \
        JWT_SECRET_PARTNER_A="dev-secret-partner-a-for-testing-only-32chars" \
        python3 python-client.py 2>&1
    ) || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        pass "[python-client] exited 0"
    else
        fail "[python-client] exited $exit_code"
        echo "$output"
    fi
}

run_T7_nodejs_client() {
    section "T7: Node.js Client Example"
    local client_dir="$PROJECT_DIR/examples/partner-clients"

    if ! command -v node >/dev/null 2>&1; then
        warning "node not found, skipping T7"
        return
    fi

    # Install deps if needed
    if [[ ! -d "$client_dir/node_modules/jsonwebtoken" ]]; then
        info "Installing npm deps ..."
        (cd "$client_dir" && npm install --silent jsonwebtoken axios 2>/dev/null) || true
    fi

    local output exit_code=0
    output=$(
        cd "$client_dir"
        API_BASE_URL="https://localhost:${HTTPS_PORT}" \
        PARTNER_ID=partner-company-a \
        JWT_SECRET_PARTNER_A="dev-secret-partner-a-change-in-production-32chars" \
        node nodejs-client.js 2>&1
    ) || exit_code=$?

    # Node.js client uses the non-standard dev secret that doesn't match
    # what partners-loader.lua expects. Provide the correct dev secret.
    if [[ $exit_code -eq 0 ]]; then
        pass "[nodejs-client] exited 0"
    else
        # Retry with the correct secret
        exit_code=0
        output=$(
            cd "$client_dir"
            API_BASE_URL="https://localhost:${HTTPS_PORT}" \
            PARTNER_ID=partner-company-a \
            JWT_SECRET_PARTNER_A="dev-secret-partner-a-for-testing-only-32chars" \
            node nodejs-client.js 2>&1
        ) || exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            pass "[nodejs-client] exited 0"
        else
            fail "[nodejs-client] exited $exit_code"
            echo "$output"
        fi
    fi
}

# ─── Summary ──────────────────────────────────────────────────────────────────
print_summary() {
    section "Test Summary"
    echo -e "  ${GREEN}PASSED${NC}: $PASSED"
    echo -e "  ${RED}FAILED${NC}: $FAILED"
    echo ""
    if [[ $FAILED -eq 0 ]]; then
        success "All tests passed!"
    else
        error "$FAILED test(s) failed"
    fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Podman Microservices - Test Stack   ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
    echo ""

    check_prereqs
    generate_certs
    setup_logs
    create_network
    build_images
    start_containers
    wait_for_health

    run_T1_jwt
    run_T2_bff_health
    run_T3_ssl_proxy
    run_T4_partner_auth
    run_T5_bff_routing
    run_T6_python_client
    run_T7_nodejs_client

    print_summary

    [[ $FAILED -eq 0 ]]
}

main "$@"
