FROM docker.io/openresty/openresty:alpine

# Install lua-resty-jwt via opm
RUN apk add --no-cache perl curl && \
    opm install SkyLothar/lua-resty-jwt && \
    apk del perl curl

# Nginx configuration
COPY services/ssl-proxy/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY services/ssl-proxy/conf.d/ /etc/nginx/conf.d/
COPY services/ssl-proxy/lua/ /usr/local/openresty/site/lualib/
RUN chmod 644 /usr/local/openresty/site/lualib/partner-auth.lua \
              /usr/local/openresty/site/lualib/partners-loader.lua

# SSL certificates are volume-mounted at runtime (never baked into image)

EXPOSE 80 443

CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]
