FROM golang:1.20-alpine
RUN apk add --no-cache ca-certificates
WORKDIR /app
COPY . .
RUN go mod download || true
RUN CGO_ENABLED=0 go build -o /app/server .
EXPOSE 8080
ENTRYPOINT ["/app/server"]
