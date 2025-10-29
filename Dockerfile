FROM golang:1.20-alpine AS builder
WORKDIR /build
COPY go.mod go.sum* ./
RUN go mod download 2>/dev/null || true
COPY main.go .
RUN CGO_ENABLED=0 GOOS=linux go build -o server main.go

FROM alpine:latest
WORKDIR /app
COPY --from=builder /build/server .
EXPOSE 8080
CMD ["/app/server"]
