# 使用官方 Go 1.20 镜像作为构建基础
FROM golang:1.20-alpine AS builder

# 设置工作目录
WORKDIR /app

# 复制 go.mod 和 go.sum（如果存在）
COPY go.mod go.sum* ./

# 下载依赖（如果有的话）
RUN go mod download || true

# 复制源代码
COPY main.go .

# 构建二进制文件
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o app .

# 使用小型基础镜像运行应用
FROM alpine:latest

# 安装 ca-certificates 用于 HTTPS
RUN apk --no-cache add ca-certificates

WORKDIR /root/

# 从构建阶段复制二进制文件
COPY --from=builder /app/app .

# 暴露端口
EXPOSE 8080

# 运行应用
CMD ["./app"]
