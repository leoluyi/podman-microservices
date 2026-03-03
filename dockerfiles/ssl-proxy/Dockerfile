# SSL Proxy Dockerfile
# Build context: project root (so COPY can reach configs/)
# Usage: podman build -f dockerfiles/ssl-proxy/Dockerfile -t <tag> .

FROM docker.io/openresty/openresty:alpine

# Install lua-resty-jwt via opm (perl + curl needed, removed after)
RUN apk add --no-cache perl curl && \
    opm install SkyLothar/lua-resty-jwt && \
    apk del perl curl

# Bake the project's Lua modules into the image.
# site/lualib is in the default OpenResty Lua search path.
# chmod 644: COPY defaults to 600 on some hosts; nginx workers run as nobody and need read access.
COPY configs/ssl-proxy/lua/partner-auth.lua   /usr/local/openresty/site/lualib/partner-auth.lua
COPY configs/ssl-proxy/lua/partners-loader.lua /usr/local/openresty/site/lualib/partners-loader.lua
RUN chmod 644 /usr/local/openresty/site/lualib/partner-auth.lua \
              /usr/local/openresty/site/lualib/partners-loader.lua
