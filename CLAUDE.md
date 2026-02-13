# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Podman-based microservices architecture for RHEL 9+ systems using Systemd Quadlet for container orchestration. The architecture implements unified SSL termination with dual authentication mechanisms for different client types.

## Essential Commands

### Build Container Images

```bash
# Build all services
for service in api-user api-order api-product bff frontend; do
    cd dockerfiles/$service
    podman build -t localhost/$service:latest .
    cd ../..
done

# Build a single service
cd dockerfiles/api-user
podman build -t localhost/api-user:latest .
```

### Development Environment Setup

```bash
# Initialize development environment (enables localhost debug ports)
./scripts/setup.sh dev

# Initialize production environment (full network isolation)
./scripts/setup.sh prod
```

### Service Management

```bash
# Start all services
./scripts/start-all.sh

# Stop all services
./scripts/stop-all.sh

# Check service status
./scripts/status.sh

# Restart a single service
./scripts/restart-service.sh <service-name>
# Example: ./scripts/restart-service.sh api-order

# View logs
./scripts/logs.sh <service-name>
# Example: ./scripts/logs.sh ssl-proxy
```

### Testing and Validation

```bash
# Run connectivity tests
./scripts/test-connectivity.sh

# Generate self-signed SSL certificates
./scripts/generate-certs.sh

# Generate JWT tokens for testing
./scripts/generate-jwt.sh <partner-id>
# Example: ./scripts/generate-jwt.sh partner-company-a
```

### Manual Service Control

```bash
# Using systemctl (--user for rootless Podman)
systemctl --user status ssl-proxy
systemctl --user restart api-order
systemctl --user logs -f bff

# Direct Podman commands
podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
podman exec -it api-order curl http://localhost:8080/health
```

## Architecture Overview

### Request Flow

The architecture uses a unified SSL termination pattern with route-based authentication:

```
Internet (HTTPS :443)
    ↓
SSL Proxy (OpenResty)
├─ SSL termination
├─ Partner JWT validation (Lua, for /partner/api/* routes)
└─ Route distribution
    ↓
    ├─→ Frontend (Nginx :80) - Static files
    ├─→ BFF Gateway (:8080) - Session auth for web/mobile
    └─→ Backend APIs (direct) - Partner API access
            ↓
    Internal Network (10.89.0.0/24)
    ├─ api-user:8080
    ├─ api-order:8080
    └─ api-product:8080
```

### Layered Authentication Strategy

**1. Web/Mobile Apps (via BFF):**
- Route: `/api/*`
- SSL Proxy: Direct proxy to BFF (no authentication)
- BFF: Session-based authentication (existing mechanism)
- Use case: Complex user state management
- Auth responsibility: BFF layer

**2. Partner APIs (direct to backend):**
- Route: `/partner/api/*`
- SSL Proxy: JWT validation using OpenResty + Lua (~30-40 lines)
- Backend: Receives X-Partner-ID header for business logic
- Use case: Fixed partners with stable auth logic
- Auth responsibility: SSL Proxy layer

### Network Isolation

**Internal Network (`internal-net`):**
- Subnet: 10.89.0.0/24
- `Internal=true` in Quadlet config ensures complete isolation
- Backend APIs are NOT accessible from outside in production mode
- Containers communicate via DNS names (e.g., `http://api-user:8080`)

**Port Strategy:**
- Production: Backend APIs have no published ports (complete isolation)
- Development: Debug ports 8101-8103 bound to 127.0.0.1 only
- All backend containers internally use port 8080 (no conflicts due to container isolation)

## Key Configuration Files

### Quadlet Service Definitions (`quadlet/`)

Systemd Quadlet files define container services with `.container` extension:
- `internal-net.network` - Defines isolated internal network
- `ssl-proxy.container` - SSL proxy with OpenResty
- `frontend.container`, `bff.container` - Frontend tier
- `api-*.container` - Backend services

**Environment Overrides:** `*.container.d/environment.conf` files provide environment-specific settings (dev mode only).

### SSL Proxy Configuration (`configs/ssl-proxy/`)

OpenResty (Nginx + Lua) configuration:
- `nginx.conf` - Main config with Lua initialization
- `conf.d/upstream.conf` - Backend service definitions
- `conf.d/routes.conf` - Routing rules + JWT validation (Partner API only)

**JWT Validation:** Implemented in `routes.conf` using `access_by_lua_block` for `/partner/api/*` routes only. Simple implementation (30-40 lines) for stable partner authentication. Web/App API (`/api/*`) is proxied directly to BFF without JWT validation.

### Environment Variables

**SSL Proxy:**
- `JWT_SECRET` - Must be changed in production (set in `quadlet/ssl-proxy.container`)
- Generate: `openssl rand -base64 32`

**Debug Ports (Dev mode only):**
- Set in `*.container.d/environment.conf`
- Format: `DEBUG_PORT_8101=127.0.0.1:8101:8080`

## Development Patterns

### Adding a New Backend Service

1. Create Dockerfile in `dockerfiles/new-service/`
2. Build image: `podman build -t localhost/new-service:latest .`
3. Copy and modify quadlet config from existing service
4. If direct partner access needed: update `configs/ssl-proxy/conf.d/upstream.conf` and `routes.conf`
5. If BFF access needed: update BFF configuration
6. Deploy: `systemctl --user daemon-reload && systemctl --user start new-service`

### Modifying JWT Validation Logic

JWT validation is in `configs/ssl-proxy/conf.d/routes.conf` using Lua blocks. Keep implementation simple (30-40 lines). For complex logic, consider moving to Backend or creating a dedicated Gateway service.

### Updating SSL Certificates

```bash
# Replace certificates in /opt/app/certs/
cp new-cert.crt /opt/app/certs/server.crt
cp new-key.key /opt/app/certs/server.key
chmod 644 /opt/app/certs/server.crt
chmod 600 /opt/app/certs/server.key

# Restart SSL proxy
./scripts/restart-service.sh ssl-proxy
```

## Service Dependencies

Quadlet services have systemd dependencies defined:
- `ssl-proxy` depends on `internal-net`, `frontend`, `bff`
- Backend APIs depend on `internal-net`
- Use `After=` and `Wants=` directives in `.container` files

Starting `ssl-proxy` will automatically start dependent services due to `Wants=` directive.

## Debugging

### Development Mode vs Production Mode

**Development (`./scripts/setup.sh dev`):**
- Creates `*.container.d/environment.conf` files
- Enables debug ports 8101-8103 on 127.0.0.1
- Allows direct backend API access: `curl http://localhost:8101/health`

**Production (`./scripts/setup.sh prod`):**
- Removes `*.container.d/` directories
- Complete network isolation for backend APIs
- Access only through SSL Proxy

### Common Issues

**Services won't start:**
```bash
systemctl --user status <service-name>
journalctl --user -u <service-name> -n 50
```

**JWT validation fails:**
- Check JWT_SECRET matches between token generation and ssl-proxy
- View logs: `./scripts/logs.sh ssl-proxy`
- Verify token: Use jwt.io to decode and check expiry

**Network connectivity issues:**
```bash
# Check network exists
podman network ls | grep internal-net

# Inspect container network
podman inspect api-user | grep -A 10 "Networks"

# Test from within container
podman exec -it bff curl http://api-user:8080/health
```

**Port conflicts:**
- Production mode should have no published ports for backend APIs
- Dev mode debug ports (8101-8103) should only bind to 127.0.0.1
- Check: `podman ps --format "table {{.Names}}\t{{.Ports}}"`

## Security Considerations

### Production Checklist

Before deploying to production:
1. Run `./scripts/setup.sh prod` to disable debug ports
2. Change JWT_SECRET in `quadlet/ssl-proxy.container`
3. Use valid SSL certificates (not self-signed)
4. Configure firewall to only allow ports 80, 443
5. Enable systemd service auto-start: `systemctl --user enable <services>`

### Defense in Depth

The architecture implements multiple security layers:
1. SSL/TLS encryption (transport layer)
2. Partner JWT validation (application layer, simplified)
3. Network isolation (network layer via `Internal=true`)
4. Resource limits (container layer via Quadlet)

## Common Workflows

### Update Backend Service Code

```bash
# 1. Rebuild image
cd dockerfiles/api-user
podman build -t localhost/api-user:latest .

# 2. Restart service (Quadlet will use new image)
cd ../..
./scripts/restart-service.sh api-user

# 3. Verify
./scripts/status.sh
./scripts/logs.sh api-user
```

### Test API Endpoints

**Web/App API (via BFF):**
```bash
# Login to get session
curl -k -X POST https://localhost/api/login \
     -d '{"username":"user","password":"pass"}' \
     -c cookies.txt

# Access API with session
curl -k https://localhost/api/orders -b cookies.txt
```

**Partner API (JWT validation at SSL Proxy):**
```bash
# 1. Generate JWT token
TOKEN=$(./scripts/generate-jwt.sh partner-company-a)

# 2. Test endpoint
curl -k -H "Authorization: Bearer $TOKEN" \
     https://localhost/partner/api/order/

# 3. Check logs for validation details
./scripts/logs.sh ssl-proxy
```

### Backup Configuration

```bash
# Backup all configs and certs
tar -czf backup-$(date +%Y%m%d).tar.gz \
    quadlet/ configs/ /opt/app/certs/
```

## Technology Stack

- **Container Runtime**: Podman 4.4+ (rootless mode)
- **Orchestration**: Systemd Quadlet
- **SSL Proxy**: OpenResty (Nginx + LuaJIT)
- **Backend**: Java/OpenJDK 17 (SUSE BCI base images)
- **Frontend**: Nginx 1.21
- **OS**: RHEL 9 / Rocky Linux 9 / AlmaLinux 9

## Important Notes

- All backend services internally use port 8080 (no conflicts due to container network isolation)
- Internal network uses `Internal=true` for complete isolation
- JWT validation is intentionally kept simple (~30-40 lines Lua) for maintainability
- Use BFF for complex authentication logic (web/mobile apps)
- Debug ports (8101-8103) are development-only and bind to localhost
- Quadlet automatically converts `.container` files to systemd services
