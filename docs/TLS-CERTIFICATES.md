# TLS Certificate Management

The ssl-proxy uses volume-mounted TLS certificates. Certificates are never baked into the container image, allowing them to be replaced without rebuilding.

## How It Works

```
Host filesystem                          Container
─────────────────                        ──────────────────
/opt/app/certs/server.crt  ──(mount)──►  /etc/nginx/ssl/server.crt
/opt/app/certs/server.key  ──(mount)──►  /etc/nginx/ssl/server.key
```

The ssl-proxy reads these paths at startup. To update certificates, replace the files on the host and restart the container.

## Local Development (Self-Signed)

The `local-start.sh` script auto-generates a self-signed certificate if none exists:

```bash
./scripts/local-start.sh
# Generates: certs/server.crt, certs/server.key
```

The generated cert:
- RSA 2048-bit, SHA-256
- Valid for 365 days
- SAN: `localhost`, `127.0.0.1`, `::1`
- Stored at `$PROJECT_ROOT/certs/` (gitignored)

To regenerate:

```bash
rm -f certs/server.crt certs/server.key
./scripts/local-start.sh
```

Or manually:

```bash
openssl req -x509 -nodes -days 365 \
    -newkey rsa:2048 \
    -keyout certs/server.key \
    -out certs/server.crt \
    -subj "/CN=localhost" \
    -addext "subjectAltName=DNS:localhost,IP:127.0.0.1,IP:::1"

chmod 644 certs/server.crt
chmod 600 certs/server.key
```

## Production (RHEL) - Mounting Real Certificates

On the RHEL guest OS, place the CA-signed certificate and private key at:

```
/opt/app/certs/server.crt    # Certificate (or full chain: cert + intermediate + root)
/opt/app/certs/server.key    # Private key
```

### File Permissions

```bash
# Certificate (readable by nginx worker process)
chmod 644 /opt/app/certs/server.crt
chown root:root /opt/app/certs/server.crt

# Private key (restricted)
chmod 600 /opt/app/certs/server.key
chown root:root /opt/app/certs/server.key
```

### Certificate Chain

If your CA provides intermediate certificates, concatenate them into `server.crt`:

```bash
cat your-domain.crt intermediate.crt root.crt > /opt/app/certs/server.crt
```

Order matters: domain cert first, root CA last.

### Quadlet Configuration

The `quadlet/ssl-proxy.container` mounts certs as read-only volumes:

```ini
Volume=/opt/app/certs/server.crt:/etc/nginx/ssl/server.crt:ro
Volume=/opt/app/certs/server.key:/etc/nginx/ssl/server.key:ro
```

No changes to the Quadlet file are needed when replacing certs.

### local-start.sh Configuration

For local development, `local-start.sh` mounts from `$PROJECT_ROOT/certs/`:

```bash
-v "$CERT_DIR/server.crt:/etc/nginx/ssl/server.crt:ro"
-v "$CERT_DIR/server.key:/etc/nginx/ssl/server.key:ro"
```

## Replacing Certificates

### Without Downtime (Nginx Reload)

```bash
# 1. Place new cert files
cp new-server.crt /opt/app/certs/server.crt
cp new-server.key /opt/app/certs/server.key
chmod 644 /opt/app/certs/server.crt
chmod 600 /opt/app/certs/server.key

# 2. Reload nginx inside the container (no downtime)
podman exec ssl-proxy nginx -s reload
```

### With Restart

```bash
# Local dev
./scripts/local-stop.sh && ./scripts/local-start.sh

# Quadlet (systemd)
systemctl --user restart ssl-proxy
```

## Verification

```bash
# Check certificate details
openssl x509 -in /opt/app/certs/server.crt -text -noout | grep -E "Subject:|Not After|DNS:|IP:"

# Check the cert served by the running proxy
echo | openssl s_client -connect localhost:8443 -servername localhost 2>/dev/null | openssl x509 -text -noout | head -20

# Verify cert matches private key (hashes should match)
openssl x509 -noout -modulus -in /opt/app/certs/server.crt | md5sum
openssl rsa  -noout -modulus -in /opt/app/certs/server.key | md5sum
```

## Certificate Expiry Monitoring

Set up a cron job or systemd timer to check expiry:

```bash
# Check days until expiry
openssl x509 -enddate -noout -in /opt/app/certs/server.crt
# notAfter=Mar 23 03:18:56 2027 GMT

# Alert if expiring within 30 days
if ! openssl x509 -checkend 2592000 -noout -in /opt/app/certs/server.crt 2>/dev/null; then
    echo "WARNING: TLS certificate expires within 30 days"
fi
```

## Directory Structure

```
project-root/
├── certs/                     # Local dev (gitignored)
│   ├── server.crt
│   ├── server.key
│   └── openssl.cnf            # Auto-generated config for self-signed cert

Production (RHEL):
/opt/app/
├── certs/                     # Mounted into ssl-proxy container
│   ├── server.crt             # CA-signed cert (or chain)
│   └── server.key             # Private key (chmod 600)
```
