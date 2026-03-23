FROM node:22-alpine AS builder
WORKDIR /app
COPY services/frontend/package.json services/frontend/package-lock.json* ./
RUN npm install
COPY services/frontend/ .
RUN npm run build

FROM registry.suse.com/suse/nginx:1.21
COPY --from=builder /app/dist /usr/share/nginx/html
COPY services/frontend/nginx.conf /etc/nginx/nginx.conf
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD curl -f http://localhost/health || exit 1
CMD ["nginx", "-g", "daemon off;"]
