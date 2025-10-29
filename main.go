package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"time"
)

// UserData 用户数据结构
type UserData struct {
	UserID    string `json:"user_id"`
	Nickname  string `json:"nickname"`
	AvatarURL string `json:"avatar_url"`
	LoginType string `json:"login_type"`
	Token     string `json:"token"`
}

// Response 通用响应结构
type Response struct {
	Code    int         `json:"code"`
	Message string      `json:"message"`
	Data    interface{} `json:"data,omitempty"`
}

func main() {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("PANIC: %v", r)
		}
	}()

	fmt.Println("🎮 麻将游戏后端服务器")
	fmt.Println("================================")
	fmt.Println("版本: 0.1.0")
	fmt.Println("状态: 开发中")
	fmt.Println("")

	// 设置路由
	http.HandleFunc("/api/auth/wechat", handleWeChatLogin)
	http.HandleFunc("/api/auth/guest", handleGuestLogin)
	http.HandleFunc("/api/health", handleHealth)

	// 启动服务器
	port := ":8080"
	fmt.Printf("🚀 服务器启动在端口 %s\n", port)
	fmt.Println("")
	fmt.Println("📡 可用的API端点:")
	fmt.Println("  POST http://localhost:8080/api/auth/wechat  - 微信登录")
	fmt.Println("  POST http://localhost:8080/api/auth/guest   - 游客登录")
	fmt.Println("  GET  http://localhost:8080/api/health       - 健康检查")
	fmt.Println("")

	log.Fatal(http.ListenAndServe(port, enableCORS(http.DefaultServeMux)))
}

// enableCORS 启用CORS中间件
func enableCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")

		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}

		next.ServeHTTP(w, r)
	})
}

// handleWeChatLogin 处理微信登录（模拟）
func handleWeChatLogin(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		respondJSON(w, http.StatusMethodNotAllowed, Response{
			Code:    405,
			Message: "Method not allowed",
		})
		return
	}

	// 模拟登录成功
	time.Sleep(500 * time.Millisecond)

	userData := UserData{
		UserID:    "wx_" + strconv.FormatInt(time.Now().UnixNano(), 10),
		Nickname:  "微信用户_" + strconv.FormatInt(time.Now().UnixNano()%10000, 10),
		AvatarURL: "https://via.placeholder.com/150",
		LoginType: "wechat",
		Token:     generateToken(),
	}

	log.Printf("✅ 微信登录成功: %s", userData.Nickname)

	respondJSON(w, http.StatusOK, Response{
		Code:    200,
		Message: "登录成功",
		Data:    userData,
	})
}

// handleGuestLogin 处理游客登录
func handleGuestLogin(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		respondJSON(w, http.StatusMethodNotAllowed, Response{
			Code:    405,
			Message: "Method not allowed",
		})
		return
	}

	userData := UserData{
		UserID:    "guest_" + strconv.FormatInt(time.Now().UnixNano(), 10),
		Nickname:  "游客_" + strconv.FormatInt(time.Now().UnixNano()%10000, 10),
		AvatarURL: "",
		LoginType: "guest",
		Token:     generateToken(),
	}

	log.Printf("✅ 游客登录成功: %s", userData.Nickname)

	respondJSON(w, http.StatusOK, Response{
		Code:    200,
		Message: "登录成功",
		Data:    userData,
	})
}

// handleHealth 健康检查
func handleHealth(w http.ResponseWriter, r *http.Request) {
	respondJSON(w, http.StatusOK, Response{
		Code:    200,
		Message: "Server is running",
		Data: map[string]interface{}{
			"version": "0.1.0",
			"status":  "healthy",
		},
	})
}

// generateToken 生成简单的token
func generateToken() string {
	return "token_" + strconv.FormatInt(time.Now().Unix(), 10)
}

// respondJSON 返回JSON响应
func respondJSON(w http.ResponseWriter, statusCode int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	json.NewEncoder(w).Encode(data)
}
