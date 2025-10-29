package main

import (
	"fmt"
	"log"
	"net/http"
)

func main() {
	fmt.Println("🎮 麻将游戏后端服务器启动")
	fmt.Println("🚀 服务器在 :8080 运行")

	http.HandleFunc("/api/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		fmt.Fprintf(w, `{"status":"ok","version":"0.1.0"}`)
	})

	log.Fatal(http.ListenAndServe(":8080", nil))
}
