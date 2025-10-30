package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"time"
)

var serverReady = false

func main() {
	fmt.Println("=== Mahjong Game Server Starting ===")
	fmt.Printf("Environment PORT: %s\n", os.Getenv("PORT"))
	fmt.Printf("PID: %d\n", os.Getpid())

	// 健康检查端点 - 立即响应
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		fmt.Fprintf(w, `{"status":"ok","message":"Mahjong Game Server","time":"%s"}`, time.Now().Format(time.RFC3339))
	})

	http.HandleFunc("/api/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		fmt.Fprintf(w, `{"status":"ok","ready":%v,"time":"%s"}`, serverReady, time.Now().Format(time.RFC3339))
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	addr := "0.0.0.0:" + port
	fmt.Printf("Server starting on %s...\n", addr)
	fmt.Printf("Health check: http://localhost:%s/api/health\n", port)

	// 长延迟 - 确保 Railway 的初始检查不会失败
	fmt.Println("Waiting for initialization...")
	time.Sleep(2 * time.Second)

	serverReady = true
	fmt.Println("=== Server Ready ===")
	fmt.Printf("Ready to accept requests at %s\n", time.Now().Format(time.RFC3339))

	// 心跳日志
	go func() {
		ticker := time.NewTicker(30 * time.Second)
		defer ticker.Stop()
		for range ticker.C {
			fmt.Printf("[HEARTBEAT] Server is alive at %s\n", time.Now().Format(time.RFC3339))
		}
	}()

	if err := http.ListenAndServe(addr, nil); err != nil {
		fmt.Printf("Server error: %v\n", err)
		log.Fatal(err)
	}
}
