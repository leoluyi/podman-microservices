# Security Headers

The ssl-proxy (OpenResty) applies security headers to all HTTPS responses. These headers are configured in `services/ssl-proxy/conf.d/routes.conf` on the HTTPS server block.

## Current Headers

| Header | Value | Purpose |
|--------|-------|---------|
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains` | Forces browsers to use HTTPS for 1 year. Prevents protocol downgrade attacks. |
| `Content-Security-Policy` | `default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self'; frame-ancestors 'self';` | Restricts resource loading origins. Mitigates XSS and data injection. |
| `X-Frame-Options` | `SAMEORIGIN` | Prevents clickjacking by disallowing embedding in iframes from other origins. |
| `X-Content-Type-Options` | `nosniff` | Prevents browsers from MIME-sniffing responses away from the declared content-type. |
| `X-XSS-Protection` | `1; mode=block` | Legacy XSS filter for older browsers. Modern browsers use CSP instead. |

All headers use the `always` directive, meaning they are sent on every response including error pages (4xx, 5xx).

## Configuration Location

```
services/ssl-proxy/conf.d/routes.conf  (lines 39-44)
```

```nginx
# HTTPS server block
server {
    listen 443 ssl http2;
    ...

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header Content-Security-Policy "default-src 'self'; ..." always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
}
```

## SSL/TLS Configuration

The ssl-proxy also enforces secure TLS settings:

```nginx
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers HIGH:!aNULL:!MD5;
ssl_prefer_server_ciphers on;

ssl_session_cache shared:SSL:10m;
ssl_session_timeout 10m;
ssl_session_tickets off;
```

- Only TLS 1.2 and 1.3 are allowed (1.0/1.1 disabled)
- Weak ciphers (aNULL, MD5) are excluded
- Session tickets are disabled to prevent forward secrecy issues

## Additional Security Measures

The ssl-proxy also provides:

- **`server_tokens off`** (in `nginx.conf`) - hides the Nginx/OpenResty version from response headers
- **Rate limiting** - IP-based (`10r/s`) and user-based (`100r/s`) via `limit_req_zone`
- **Generic error pages** - 401, 403, 5xx responses use sanitized JSON messages, never exposing internal details

## Future Migration Notes

When migrating to a real API gateway (e.g., Kong, APISIX, or Spring Cloud Gateway with SSL), ensure these headers are replicated. Key considerations:

1. **HSTS** - must be set at the TLS termination point. If the API gateway terminates SSL, move this header there.
2. **CSP** - the `'unsafe-inline'` and `'unsafe-eval'` directives for `script-src` are needed for the current React frontend. Tighten these (use nonces or hashes) when the frontend build pipeline supports it.
3. **X-Frame-Options** - `frame-ancestors` in CSP is the modern replacement. Both are set currently for compatibility with older browsers.
4. **X-XSS-Protection** - deprecated in modern browsers (Chrome removed it). Can be dropped once legacy browser support is no longer needed.

## Testing Headers

```bash
# Verify all security headers are present
curl -sI https://localhost:8443/ -k | grep -iE '^(strict|content-security|x-frame|x-content|x-xss)'

# Expected output:
# Strict-Transport-Security: max-age=31536000; includeSubDomains
# Content-Security-Policy: default-src 'self'; ...
# X-Frame-Options: SAMEORIGIN
# X-Content-Type-Options: nosniff
# X-XSS-Protection: 1; mode=block
```
