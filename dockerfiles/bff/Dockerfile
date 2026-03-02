# BFF Service Dockerfile
# Multi-stage build: SUSE BCI Go builder + BCI Base runtime

# Stage 1: build
FROM registry.suse.com/bci/golang:1.23 AS builder
WORKDIR /build
COPY main.go .
RUN go mod init bff && \
    CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o bff .

# Stage 2: runtime
FROM registry.suse.com/bci/bci-base:latest
RUN zypper --non-interactive install curl && zypper clean

WORKDIR /app
COPY --from=builder /build/bff .

LABEL maintainer="your-team@example.com"
LABEL description="BFF (Backend For Frontend) Gateway Service"
LABEL version="1.0.0"

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD curl -sf http://localhost:8080/health || exit 1

CMD ["./bff"]
