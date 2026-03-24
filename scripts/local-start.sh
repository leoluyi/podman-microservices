#!/bin/bash
# ============================================================================
# local-start.sh - Start full stack via plain podman (no systemd/Quadlet)
# ============================================================================
# For local development on machines without systemd (e.g., macOS).
# Services stay running after the script exits -- use local-stop.sh to tear down.
#
# Usage: ./scripts/local-start.sh [--skip-build]
# ============================================================================

set -euo pipefail

source "$(dirname "$0")/lib.sh"

# shellcheck source=../configs/images.env
source "$PROJECT_ROOT/configs/images.env"

NETWORK="internal-net"
CERT_DIR="$PROJECT_ROOT/certs"
LOG_DIR="$PROJECT_ROOT/logs/ssl-proxy"
LABEL="app=microservices"

HTTPS_PORT="${HTTPS_PORT:-8443}"
HTTP_PORT="${HTTP_PORT:-8080}"

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
    local pids=()

    info "Building all images in parallel ..."

    podman build -t "$API_AUTH_IMAGE" \
        -f "$PROJECT_ROOT/services/api-auth/Dockerfile" \
        "$PROJECT_ROOT/services" --quiet &
    pids+=($!)

    podman build -t "$API_USER_IMAGE" \
        -f "$PROJECT_ROOT/services/api-user/Dockerfile" \
        "$PROJECT_ROOT/services" --quiet &
    pids+=($!)

    podman build -t "$API_ORDER_IMAGE" \
        -f "$PROJECT_ROOT/services/api-order/Dockerfile" \
        "$PROJECT_ROOT/services" --quiet &
    pids+=($!)

    podman build -t "$API_PRODUCT_IMAGE" \
        -f "$PROJECT_ROOT/services/api-product/Dockerfile" \
        "$PROJECT_ROOT/services" --quiet &
    pids+=($!)

    podman build -t "$BFF_IMAGE" \
        -f "$PROJECT_ROOT/services/bff/Dockerfile" \
        "$PROJECT_ROOT/services" --quiet &
    pids+=($!)

    podman build -t "$FRONTEND_IMAGE" \
        -f "$PROJECT_ROOT/services/frontend/Dockerfile" \
        "$PROJECT_ROOT" --quiet &
    pids+=($!)

    podman build -t "$SSL_PROXY_IMAGE" \
        -f "$PROJECT_ROOT/services/ssl-proxy/Dockerfile" \
        "$PROJECT_ROOT" --quiet &
    pids+=($!)

    local failed=0
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            failed=$((failed + 1))
        fi
    done

    if [[ $failed -gt 0 ]]; then
        error "$failed image build(s) failed"
        return 1
    fi

    success "All images built"
}

# ─── Volume mount permissions ──────────────────────────────────────────────
# Rootless podman on macOS maps host UIDs differently inside containers.
# Files bind-mounted with :ro must be world-readable so the container process
# (running as a non-root user) can access them. This step is idempotent.
fix_mount_permissions() {
    section "Mount Permissions"
    # Config files mounted into Spring Boot services
    find "$PROJECT_ROOT/services"/*/config -name "*.yml" -exec chmod a+r {} + 2>/dev/null || true
    # PostgreSQL init script (needs read + execute)
    chmod a+rx "$PROJECT_ROOT/configs/shared/postgres/init-db.sh" 2>/dev/null || true
    # Frontend nginx config
    chmod a+r "$PROJECT_ROOT/services/frontend/nginx.conf" 2>/dev/null || true
    # SSL certs (key needs read for nginx inside container)
    chmod a+r "$CERT_DIR/server.crt" "$CERT_DIR/server.key" 2>/dev/null || true
    # SSL proxy configs
    chmod -R a+rX "$PROJECT_ROOT/configs/shared/ssl-proxy" 2>/dev/null || true
    success "Mount permissions fixed"
}

# ─── Container startup helpers ──────────────────────────────────────────────

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

# Helper: start a Spring Boot service with config mounts and env secrets
start_spring_service() {
    local service=$1 image=$2
    shift 2
    start_replicas "$service" "$image" 8080 \
        -e SPRING_PROFILES_ACTIVE=dev \
        -e DB_PASSWORD="$(cat "$PROJECT_ROOT/secrets/db-password")" \
        -e JWT_SIGNING_KEY="$(cat "$PROJECT_ROOT/secrets/jwt-signing-key")" \
        -v "$PROJECT_ROOT/services/${service}/config/application-dev.yml:/app/config/application-dev.yml:ro" \
        "$@"
}

start_postgres() {
    section "PostgreSQL"
    local name="postgres"
    if podman container exists "$name" 2>/dev/null; then
        warning "$name already running, skipping"
        return
    fi
    info "Starting $name ..."
    podman run -d --name "$name" \
        --network "$NETWORK" \
        --network-alias postgres \
        --label "$LABEL" \
        -e POSTGRES_PASSWORD="$(cat "$PROJECT_ROOT/secrets/postgres-password")" \
        -e APP_USER_PASSWORD="$(cat "$PROJECT_ROOT/secrets/db-password")" \
        -v "$PROJECT_ROOT/configs/shared/postgres/init-db.sh:/docker-entrypoint-initdb.d/init-db.sh:ro" \
        -v "pgdata:/var/lib/postgresql/data" \
        "$POSTGRES_IMAGE"
    success "$name started"
}

start_auth() {
    section "Auth Service"
    start_spring_service api-auth "$API_AUTH_IMAGE"
}

start_api_services() {
    section "API Services"
    local pids=()
    start_spring_service api-user    "$API_USER_IMAGE" & pids+=($!)
    start_spring_service api-order   "$API_ORDER_IMAGE" & pids+=($!)
    start_spring_service api-product "$API_PRODUCT_IMAGE" & pids+=($!)

    local failed=0
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then failed=$((failed + 1)); fi
    done
    if [[ $failed -gt 0 ]]; then
        error "$failed API service(s) failed to start"
        return 1
    fi
}

start_bff() {
    section "BFF Gateway"
    start_spring_service bff "$BFF_IMAGE"
}

start_frontend() {
    section "Frontend"
    start_replicas frontend "$FRONTEND_IMAGE" 80 \
        -v "$PROJECT_ROOT/services/frontend/nginx.conf:/etc/nginx/nginx.conf:ro" \
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

    # nginx resolves all upstream hostnames at startup. Podman network DNS
    # may not be ready yet, so retry a few times if the container exits
    # immediately with "host not found in upstream".
    local max_attempts=5
    for attempt in $(seq 1 "$max_attempts"); do
        info "Starting $name (attempt $attempt/$max_attempts) ..."
        podman run -d --name "$name" \
            --network "$NETWORK" \
            --label "$LABEL" \
            -p "${HTTPS_PORT}:443" \
            -p "${HTTP_PORT}:80" \
            -v "$CERT_DIR/server.crt:/etc/nginx/ssl/server.crt:ro" \
            -v "$CERT_DIR/server.key:/etc/nginx/ssl/server.key:ro" \
            -v "$PROJECT_ROOT/configs/shared/ssl-proxy/nginx.conf:/usr/local/openresty/nginx/conf/nginx.conf:ro" \
            -v "$PROJECT_ROOT/configs/shared/ssl-proxy/conf.d:/etc/nginx/conf.d:ro" \
            -v "$LOG_DIR:/var/log/nginx:rw" \
            -e JWT_SECRET_PARTNER_A="dev-secret-partner-a-for-testing-only-32chars" \
            -e JWT_SECRET_PARTNER_B="dev-secret-partner-b-for-testing-only-32chars" \
            -e JWT_SECRET_PARTNER_C="dev-secret-partner-c-for-testing-only-32chars" \
            -e DEBUG_PARTNERS=true \
            "$SSL_PROXY_IMAGE"

        sleep 1
        local state
        state=$(podman inspect --format '{{.State.Status}}' "$name" 2>/dev/null || echo "unknown")
        if [[ "$state" == "running" ]]; then
            success "$name started"
            return
        fi

        warning "$name exited (attempt $attempt/$max_attempts)"
        podman logs --tail 5 "$name" 2>&1 || true
        podman rm -f "$name" >/dev/null 2>&1 || true
        sleep 1
    done

    error "$name failed to start after $max_attempts attempts"
    return 1
}

# ─── Health checks ──────────────────────────────────────────────────────────
wait_for_postgres() {
    local timeout=60 elapsed=0
    info "Waiting for PostgreSQL ..."
    while ! podman exec postgres pg_isready -U postgres -q 2>/dev/null; do
        if ! podman container exists postgres 2>/dev/null; then
            error "PostgreSQL container does not exist"
            return 1
        fi
        local state
        state=$(podman inspect --format '{{.State.Status}}' postgres 2>/dev/null || echo "unknown")
        if [[ "$state" == "exited" || "$state" == "stopped" ]]; then
            error "PostgreSQL exited unexpectedly (state=$state)"
            podman logs --tail 20 postgres 2>&1 || true
            return 1
        fi
        sleep 2
        elapsed=$((elapsed + 2))
        if [[ $elapsed -ge $timeout ]]; then
            error "PostgreSQL did not become ready within ${timeout}s"
            return 1
        fi
    done
    success "PostgreSQL is ready"
}

wait_for_health() {
    section "Health Checks"
    local timeout=120

    wait_http() {
        local label=$1 url=$2 elapsed=0
        local container_name="ssl-proxy"
        info "Waiting for $label ..."
        while ! curl -sk --max-time 3 "$url" >/dev/null 2>&1; do
            if ! podman container exists "$container_name" 2>/dev/null; then
                error "$label container ($container_name) does not exist"
                return 1
            fi
            local state
            state=$(podman inspect --format '{{.State.Status}}' "$container_name" 2>/dev/null || echo "unknown")
            if [[ "$state" == "exited" || "$state" == "stopped" ]]; then
                error "$label container exited unexpectedly (state=$state)"
                podman logs --tail 20 "$container_name" 2>&1 || true
                return 1
            fi
            sleep 2
            elapsed=$((elapsed + 2))
            if [[ $elapsed -ge $timeout ]]; then
                error "$label did not become healthy within ${timeout}s"
                info "Container state: $state"
                podman logs --tail 20 "$container_name" 2>&1 || true
                return 1
            fi
        done
        success "$label is up"
    }

    wait_http "ssl-proxy (HTTPS)" "https://localhost:${HTTPS_PORT}/health"
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
    fix_mount_permissions
    create_network

    if [[ "$SKIP_BUILD" == true ]]; then
        info "Skipping image builds (--skip-build)"
    else
        build_images
    fi

    start_postgres
    wait_for_postgres

    # All Spring Boot services can start concurrently (only need postgres)
    local pids=()
    start_auth & pids+=($!)
    start_api_services & pids+=($!)

    local failed=0
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then failed=$((failed + 1)); fi
    done
    if [[ $failed -gt 0 ]]; then
        error "Spring Boot service startup failed"
        return 1
    fi

    # BFF + frontend are independent of each other
    pids=()
    start_bff & pids+=($!)
    start_frontend & pids+=($!)

    failed=0
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then failed=$((failed + 1)); fi
    done
    if [[ $failed -gt 0 ]]; then
        error "BFF/frontend startup failed"
        return 1
    fi

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

SKIP_BUILD=false
for arg in "$@"; do
    [[ "$arg" == "--skip-build" ]] && SKIP_BUILD=true
done

main "$@"
