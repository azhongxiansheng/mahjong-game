FROM golang:1.20
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download || true
COPY . .
RUN go build -o server .
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]
