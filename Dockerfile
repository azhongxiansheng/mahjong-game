FROM golang:1.20 as builder
WORKDIR /build
COPY . .
RUN go build -o app main.go

FROM golang:1.20
WORKDIR /app
COPY --from=builder /build/app .
EXPOSE 8080
CMD ["./app"]
