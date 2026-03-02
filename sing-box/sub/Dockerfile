# ==============================================================================
# 多阶段构建：最终镜像仅包含静态二进制，约 10MB
# ==============================================================================

# 阶段 1：编译
FROM golang:1.22-alpine AS builder

WORKDIR /build
COPY go.mod .
COPY main.go .

# CGO_ENABLED=0 确保静态链接，无需 glibc
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o sub .

# 阶段 2：运行时（最小化镜像）
FROM alpine:latest

# 添加 CA 证书（用于探测公网 IP 时的 HTTPS 请求）
RUN apk add --no-cache ca-certificates

WORKDIR /
COPY --from=builder /build/sub /sub

EXPOSE 8080

CMD ["/sub"]
