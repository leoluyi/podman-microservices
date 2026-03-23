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
CMD ["nginx", "-g", "daemon off;"]
