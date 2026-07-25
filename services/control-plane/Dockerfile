# #255 Control Plane 测试镜像（不扩张根 main.go）。
# 网络端到端未验证。
FROM golang:1.25-bookworm AS build

WORKDIR /src
ENV GOTOOLCHAIN=auto
ENV CGO_ENABLED=0

# 复制 module 与源码；使用 go mod vendor 生成内容规避构建期代理不稳。
COPY go.mod go.sum ./
COPY vendor/ ./vendor/
COPY cmd/ ./cmd/
COPY internal/ ./internal/
RUN go build -mod=vendor -trimpath -ldflags="-s -w" -o /out/control-plane ./cmd/control-plane

FROM debian:bookworm-slim AS runtime

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl \
  && rm -rf /var/lib/apt/lists/*

COPY --from=build /out/control-plane /usr/local/bin/control-plane

ENV HTTP_ADDR=":8081"
ENV REDIS_ADDR="redis:6379"
ENV TOKEN_SIGNING_SECRET=""
ENV WORKER_REGISTRATION_TOKEN=""
# 遗留可选；匹配不再依赖静态 WORKER_ENDPOINT。
ENV WORKER_ENDPOINT=""
ENV VOICE_WORKER_ENDPOINT=""

EXPOSE 8081

HEALTHCHECK --interval=3s --timeout=3s --start-period=10s --retries=10 \
  CMD curl -fsS "http://127.0.0.1:8081/readyz" >/dev/null

USER nobody
ENTRYPOINT ["/usr/local/bin/control-plane"]
