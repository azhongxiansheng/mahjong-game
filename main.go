package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"time"
)

func main() {
	// 诊断信息
	fmt.Println("=== Mahjong Game Server Starting ===")
	fmt.Printf("Environment PORT: %s\n", os.Getenv("PORT"))
	fmt.Printf("PID: %d\n", os.Getpid())

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		fmt.Fprintf(w, `{"status":"ok","message":"Mahjong Game Server","time":"%s"}`, time.Now().Format(time.RFC3339))
	})

	http.HandleFunc("/api/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		fmt.Fprintf(w, `{"status":"ok","time":"%s"}`, time.Now().Format(time.RFC3339))
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	addr := "0.0.0.0:" + port
	fmt.Printf("Server starting on %s...\n", addr)
	fmt.Printf("Health check: http://localhost:%s/api/health\n", port)
	fmt.Println("=== Server Ready ===")

	if err := http.ListenAndServe(addr, nil); err != nil {
		fmt.Printf("Server error: %v\n", err)
		log.Fatal(err)
	}
}
