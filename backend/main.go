package main

import (
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"net/http"
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

func Main() {
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

	// TODO: 实现真实的微信OAuth流程
	// 1. 接收code参数
	// 2. 调用微信API获取access_token
	// 3. 获取用户信息
	// 4. 保存到数据库
	// 5. 生成JWT token

	// 模拟登录成功
	time.Sleep(500 * time.Millisecond) // 模拟网络延迟

	userData := UserData{
		UserID:    fmt.Sprintf("wx_%d", rand.Int63()),
		Nickname:  fmt.Sprintf("微信用户%d", rand.Intn(10000)),
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

	// 创建游客账号
	userData := UserData{
		UserID:    fmt.Sprintf("guest_%d", rand.Int63()),
		Nickname:  fmt.Sprintf("游客%d", rand.Intn(10000)),
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

// generateToken 生成简单的token（生产环境应使用JWT）
func generateToken() string {
	return fmt.Sprintf("token_%d_%d", time.Now().Unix(), rand.Int63())
}

// respondJSON 返回JSON响应
func respondJSON(w http.ResponseWriter, statusCode int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	json.NewEncoder(w).Encode(data)
}
