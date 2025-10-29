package main

import (
	"fmt"
	"net"
	"net/http"
	"os"
)

func main() {
	// 获取端口，默认 8080
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	
	addr := ":" + port
	
	// 启动日志
	fmt.Printf("🎮 麻将游戏后端服务器启动\n")
	fmt.Printf("🚀 服务器在 %s 运行\n", addr)
	
	// 健康检查端点
	http.HandleFunc("/api/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		fmt.Fprintf(w, `{"status":"ok","version":"0.1.0"}`)
	})
	
	// 创建监听器（用于更好的错误诊断）
	listener, err := net.Listen("tcp", addr)
	if err != nil {
		fmt.Fprintf(os.Stderr, "❌ 无法监听 %s: %v\n", addr, err)
		os.Exit(1)
	}
	defer listener.Close()
	
	// 启动服务器
	fmt.Printf("✅ 服务器已启动，等待连接...\n")
	if err := http.Serve(listener, nil); err != nil {
		fmt.Fprintf(os.Stderr, "❌ 服务器错误: %v\n", err)
		os.Exit(1)
	}
}
