# 多阶段构建：镜像小、攻击面小
# Stage 1: 构建
FROM golang:1.22-alpine AS builder

# 安全设置
RUN apk add --no-cache git ca-certificates

WORKDIR /app

# 单独下载依赖（更好的缓存）
COPY go.mod go.sum* ./
RUN go mod download

COPY . .

# 静态编译
RUN CGO_ENABLED=0 GOOS=linux go build \
    -ldflags='-w -s -extldflags "-static"' \
    -o /app/checkout-api ./cmd

# Stage 2: 运行时 - 极小基础镜像
FROM gcr.io/distroless/static-debian12:nonroot

# 复制 CA 证书和二进制
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /app/checkout-api /checkout-api

# distroless 已经包含 nonroot 用户（UID 65532）
USER nonroot:nonroot

EXPOSE 8080 9090

ENTRYPOINT ["/checkout-api"]
