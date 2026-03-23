FROM docker.io/openresty/openresty:1.27.1.2-0-alpine

# Install Lua JWT dependencies
RUN apk add --no-cache gcc musl-dev \
    && /usr/local/openresty/luajit/bin/luarocks install lua-resty-jwt 0.2.3 \
    && apk del gcc musl-dev

# Nginx configuration
COPY services/ssl-proxy/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY services/ssl-proxy/conf.d/ /etc/nginx/conf.d/
COPY services/ssl-proxy/lua/ /usr/local/openresty/site/lualib/

# SSL certificates are volume-mounted at runtime (never baked into image)

EXPOSE 80 443

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD curl -fk https://localhost/health || exit 1

CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]
