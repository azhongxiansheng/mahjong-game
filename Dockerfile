FROM golang:1.20-alpine
WORKDIR /app
COPY . .
RUN go mod download || true
RUN CGO_ENABLED=0 go build -o server .
EXPOSE 8080
CMD ["./server"]
