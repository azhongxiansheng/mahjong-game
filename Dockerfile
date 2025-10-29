FROM golang:1.20-alpine

WORKDIR /app

# Copy all files
COPY . .

# Build the application
RUN go build -o app main.go

# Expose port
EXPOSE 8080

# Set environment
ENV PORT=8080

# Run the application
CMD ["./app"]
