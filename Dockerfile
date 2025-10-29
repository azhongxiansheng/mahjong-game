FROM golang:1.20
WORKDIR /app
COPY . .
RUN go build -o app main.go
EXPOSE 8080
ENV PORT=8080
CMD ["./app"]
