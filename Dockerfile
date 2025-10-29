# Stage 1: Build
FROM golang:1.20-alpine AS builder

WORKDIR /build

# 复制源代码
COPY main.go .
COPY go.mod .
COPY go.sum* .

# 编译
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o app main.go

# Stage 2: Runtime
FROM alpine:latest

RUN apk --no-cache add ca-certificates

WORKDIR /root

# 从构建阶段复制二进制文件
COPY --from=builder /build/app .

EXPOSE 8080

ENV PORT=8080

CMD ["./app"]
