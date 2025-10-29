FROM golang:1.20-bullseye AS builder
WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-w -s" -o server .

FROM gcr.io/distroless/static-debian11
COPY --from=builder /build/server /server
EXPOSE 8080
CMD ["/server"]
