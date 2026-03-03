# API-Product Service Dockerfile (Go stub)
# Multi-stage: golang:1.23-alpine builder + alpine:3 runtime

FROM golang:1.23-alpine AS builder
WORKDIR /build
COPY main.go .
RUN go mod init api-product && \
    CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o api-product .

FROM alpine:3
RUN apk add --no-cache curl
WORKDIR /app
COPY --from=builder /build/api-product .

LABEL maintainer="your-team@example.com"
LABEL description="Product API Service (Go stub)"
LABEL version="1.0.0"

ENV SERVICE_NAME=api-product

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD curl -sf http://localhost:8080/health || exit 1

CMD ["./api-product"]
