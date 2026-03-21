#!/bin/bash
# ============================================================================
# local-start.sh - Start full stack via plain podman (no systemd/Quadlet)
# ============================================================================
# For local development on machines without systemd (e.g., macOS).
# Services stay running after the script exits -- use local-stop.sh to tear down.
#
# Usage: ./scripts/local-start.sh
# ============================================================================

set -euo pipefail

source "$(dirname "$0")/lib.sh"

# Load image names from configs/images.env
# shellcheck source=../configs/images.env
source "$PROJECT_ROOT/configs/images.env"

NETWORK="internal-net"
CERT_DIR="$PROJECT_ROOT/certs"
LOG_DIR="$PROJECT_ROOT/logs/ssl-proxy"
LABEL="app=microservices"

# Host port mappings (high ports to avoid rootless privilege issues on macOS)
HTTPS_PORT="${HTTPS_PORT:-8443}"
HTTP_PORT="${HTTP_PORT:-8080}"

# ─── Colour / section helper ────────────────────────────────────────────────
CYAN='\033[0;36m'
section() { echo -e "\n${CYAN}== $* ==${NC}"; }

# ─── Prerequisites ──────────────────────────────────────────────────────────
check_prereqs() {
    section "Prerequisites"
    local missing=()
    for cmd in podman openssl curl; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required tools: ${missing[*]}"
        exit 1
    fi
    success "All prerequisites satisfied"
}

# ─── Network ────────────────────────────────────────────────────────────────
create_network() {
    section "Network"
    if podman network exists "$NETWORK" 2>/dev/null; then
        info "Network $NETWORK already exists, reusing"
    else
        podman network create "$NETWORK"
        success "Network $NETWORK created"
    fi
}

# ─── SSL certs ──────────────────────────────────────────────────────────────
ensure_certs() {
    section "SSL Certificates"
    if [[ -f "$CERT_DIR/server.crt" && -f "$CERT_DIR/server.key" ]]; then
        info "Certs already exist at $CERT_DIR"
        return
    fi

    info "Generating self-signed cert in $CERT_DIR"
    mkdir -p "$CERT_DIR"

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
O  = Development
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

# ─── Log directory ──────────────────────────────────────────────────────────
ensure_log_dir() {
    mkdir -p "$LOG_DIR"
    info "Log dir: $LOG_DIR"
}

# ─── Image builds ───────────────────────────────────────────────────────────
build_images() {
    section "Building Images"

    info "Building api-user ..."
    podman build -t "$API_USER_IMAGE" \
        "$PROJECT_ROOT/dockerfiles/api-user" --quiet

    info "Building api-order ..."
    podman build -t "$API_ORDER_IMAGE" \
        "$PROJECT_ROOT/dockerfiles/api-order" --quiet

    info "Building api-product ..."
    podman build -t "$API_PRODUCT_IMAGE" \
        "$PROJECT_ROOT/dockerfiles/api-product" --quiet

    info "Building bff ..."
    podman build -t "$BFF_IMAGE" \
        "$PROJECT_ROOT/dockerfiles/bff" --quiet

    info "Building frontend ..."
    podman build -t "$FRONTEND_IMAGE" \
        "$PROJECT_ROOT/dockerfiles/frontend" --quiet

    info "Building ssl-proxy ..."
    podman build -t "$SSL_PROXY_IMAGE" \
        -f "$PROJECT_ROOT/dockerfiles/ssl-proxy/Dockerfile" \
        "$PROJECT_ROOT" --quiet

    success "All images built"
}

# ─── Container startup helpers ──────────────────────────────────────────────

# Start N replicas of a scalable service.
# Each container gets two network aliases:
#   - "{service}-{i}" (instance-specific, used by upstream.conf)
#   - "{service}"     (generic, enables DNS round-robin for BFF)
# Usage: start_replicas <service> <image> <port> [extra podman args...]
start_replicas() {
    local service=$1 image=$2 port=$3
    shift 3
    local replicas
    replicas=$(get_replicas "$service")
    info "Starting $service ($replicas replica(s)) ..."

    for i in $(seq 1 "$replicas"); do
        local name="${service}-${i}"
        if podman container exists "$name" 2>/dev/null; then
            warning "  $name already running, skipping"
            continue
        fi
        podman run -d --name "$name" \
            --network "$NETWORK" \
            --network-alias "$name" \
            --network-alias "$service" \
            --label "$LABEL" \
            -e SERVICE_NAME="$service" \
            -e SERVICE_INSTANCE="$i" \
            -e SERVICE_PORT="$port" \
            "$@" \
            "$image"
        success "  $name started"
    done
}

start_api_services() {
    section "API Services"
    start_replicas api-user    "$API_USER_IMAGE"    8080
    start_replicas api-order   "$API_ORDER_IMAGE"   8080
    start_replicas api-product "$API_PRODUCT_IMAGE" 8080
}

start_bff() {
    section "BFF Gateway"
    # BFF uses generic DNS aliases (e.g., "api-user") for round-robin across replicas
    start_replicas bff "$BFF_IMAGE" 8080 \
        -e API_USER_URL="http://api-user:8080" \
        -e API_ORDER_URL="http://api-order:8080" \
        -e API_PRODUCT_URL="http://api-product:8080"
}

start_frontend() {
    section "Frontend"
    start_replicas frontend "$FRONTEND_IMAGE" 80 \
        -e NGINX_HOST=localhost \
        -e NGINX_PORT=80
}

start_ssl_proxy() {
    section "SSL Proxy"
    local name="ssl-proxy"
    if podman container exists "$name" 2>/dev/null; then
        warning "$name already running, skipping"
        return
    fi
    info "Starting $name ..."
    podman run -d --name "$name" \
        --network "$NETWORK" \
        --label "$LABEL" \
        -p "${HTTPS_PORT}:443" \
        -p "${HTTP_PORT}:80" \
        -v "$CERT_DIR/server.crt:/etc/nginx/ssl/server.crt:ro" \
        -v "$CERT_DIR/server.key:/etc/nginx/ssl/server.key:ro" \
        -v "$PROJECT_ROOT/configs/ssl-proxy/nginx.conf:/usr/local/openresty/nginx/conf/nginx.conf:ro" \
        -v "$PROJECT_ROOT/configs/ssl-proxy/conf.d:/etc/nginx/conf.d:ro" \
        -v "$LOG_DIR:/var/log/nginx:rw" \
        -e JWT_SECRET_PARTNER_A="dev-secret-partner-a-for-testing-only-32chars" \
        -e JWT_SECRET_PARTNER_B="dev-secret-partner-b-for-testing-only-32chars" \
        -e JWT_SECRET_PARTNER_C="dev-secret-partner-c-for-testing-only-32chars" \
        -e DEBUG_PARTNERS=true \
        "$SSL_PROXY_IMAGE"
    success "$name started"
}

# ─── Health checks ──────────────────────────────────────────────────────────
wait_for_health() {
    section "Health Checks"
    local timeout=60

    wait_http() {
        local label=$1 url=$2 elapsed=0
        info "Waiting for $label ..."
        while ! curl -sk --max-time 3 "$url" >/dev/null 2>&1; do
            sleep 2
            elapsed=$((elapsed + 2))
            if [[ $elapsed -ge $timeout ]]; then
                error "$label did not become healthy within ${timeout}s"
                return 1
            fi
        done
        success "$label is up"
    }

    wait_http "ssl-proxy (HTTPS)" "https://localhost:${HTTPS_PORT}/health"
    wait_http "ssl-proxy (HTTP)"  "http://localhost:${HTTP_PORT}/"
}

# ─── Main ───────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${CYAN}+--------------------------------------+${NC}"
    echo -e "${CYAN}|  Podman Microservices - Local Start   |${NC}"
    echo -e "${CYAN}+--------------------------------------+${NC}"
    echo ""

    check_prereqs
    ensure_certs
    ensure_log_dir
    create_network
    build_images

    start_api_services
    start_bff
    start_frontend
    start_ssl_proxy

    wait_for_health

    echo ""
    success "All services are running!"
    echo ""
    info "Access URLs:"
    echo "  HTTPS: https://localhost:${HTTPS_PORT}/"
    echo "  HTTP:  http://localhost:${HTTP_PORT}/ (redirects to HTTPS)"
    echo ""
    info "Useful commands:"
    echo "  podman ps --filter label=$LABEL"
    echo "  ./scripts/test-connectivity.sh"
    echo "  ./scripts/local-stop.sh"
}

main "$@"
