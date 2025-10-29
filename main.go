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
	
	// 在启动监听之前等待一下，确保一切准备好
	time.Sleep(500 * time.Millisecond)
	
	fmt.Println("=== Server Ready ===")
	fmt.Printf("Ready to accept requests at %s\n", time.Now().Format(time.RFC3339))

	// 心跳日志 - 防止Railway认为应用空闲
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
