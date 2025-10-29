package main

import (
	"encoding/json"
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/gorilla/websocket"
)

// BenchmarkWebSocketConnectionPool 基准测试连接池性能
func BenchmarkWebSocketConnectionPool(b *testing.B) {
	pool := NewConnectionPool()
	go pool.Run()

	b.ResetTimer()

	for i := 0; i < b.N; i++ {
		userID := fmt.Sprintf("user_%d", i)
		conn := &websocket.Conn{}
		userConn := NewUserConnection(userID, conn)
		pool.register <- userConn
	}

	b.StopTimer()
	fmt.Printf("连接数: %d\n", pool.GetConnectionCount())
}

// BenchmarkWebSocketBroadcast 基准测试广播性能
func BenchmarkWebSocketBroadcast(b *testing.B) {
	pool := NewConnectionPool()
	go pool.Run()

	// 创建 1000 个连接
	for i := 0; i < 1000; i++ {
		userID := fmt.Sprintf("user_%d", i)
		conn := &websocket.Conn{}
		userConn := NewUserConnection(userID, conn)
		pool.register <- userConn

		// 启动写入协程
		go func(uc *UserConnection) {
			for msg := range uc.Send {
				_ = msg
			}
		}(userConn)
	}

	time.Sleep(100 * time.Millisecond)

	msg := &WebSocketMessage{
		Type:      "broadcast",
		Timestamp: time.Now().Unix(),
		UserID:    "system",
		Data:      []byte(`{"test": "data"}`),
	}

	b.ResetTimer()

	for i := 0; i < b.N; i++ {
		pool.broadcast <- msg
	}

	b.StopTimer()
}

// BenchmarkWebSocketSendToUser 基准测试单用户发送性能
func BenchmarkWebSocketSendToUser(b *testing.B) {
	pool := NewConnectionPool()
	go pool.Run()

	// 创建 100 个连接
	for i := 0; i < 100; i++ {
		userID := fmt.Sprintf("user_%d", i)
		conn := &websocket.Conn{}
		userConn := NewUserConnection(userID, conn)
		pool.register <- userConn

		go func(uc *UserConnection) {
			for msg := range uc.Send {
				_ = msg
			}
		}(userConn)
	}

	time.Sleep(100 * time.Millisecond)

	msg := &WebSocketMessage{
		Type:      "test",
		Timestamp: time.Now().Unix(),
		UserID:    "system",
		Data:      []byte(`{"test": "data"}`),
	}

	b.ResetTimer()

	for i := 0; i < b.N; i++ {
		userID := fmt.Sprintf("user_%d", i%100)
		pool.SendToUser(userID, msg)
	}

	b.StopTimer()
}

// BenchmarkWebSocketConcurrentSend 基准测试并发发送性能
func BenchmarkWebSocketConcurrentSend(b *testing.B) {
	pool := NewConnectionPool()
	go pool.Run()

	// 创建 500 个连接
	for i := 0; i < 500; i++ {
		userID := fmt.Sprintf("user_%d", i)
		conn := &websocket.Conn{}
		userConn := NewUserConnection(userID, conn)
		pool.register <- userConn

		go func(uc *UserConnection) {
			for msg := range uc.Send {
				_ = msg
			}
		}(userConn)
	}

	time.Sleep(100 * time.Millisecond)

	msg := &WebSocketMessage{
		Type:      "test",
		Timestamp: time.Now().Unix(),
		UserID:    "system",
		Data:      []byte(`{"test": "data"}`),
	}

	b.ResetTimer()

	var wg sync.WaitGroup
	concurrency := 10

	for i := 0; i < b.N; i += concurrency {
		for j := 0; j < concurrency; j++ {
			wg.Add(1)
			go func(idx int) {
				defer wg.Done()
				userID := fmt.Sprintf("user_%d", idx%500)
				pool.SendToUser(userID, msg)
			}(i + j)
		}
	}

	wg.Wait()
	b.StopTimer()
}

// BenchmarkNotificationSerialization 基准测试通知序列化性能
func BenchmarkNotificationSerialization(b *testing.B) {
	type NotificationData struct {
		ID        string `json:"id"`
		Type      string `json:"type"`
		Title     string `json:"title"`
		Content   string `json:"content"`
		Timestamp int64  `json:"timestamp"`
		Priority  int    `json:"priority"`
	}

	notif := NotificationData{
		ID:        "notif_123",
		Type:      "friend_request",
		Title:     "好友请求",
		Content:   "用户 A 请求添加你为好友",
		Timestamp: time.Now().Unix(),
		Priority:  1,
	}

	b.ResetTimer()

	for i := 0; i < b.N; i++ {
		data, _ := json.Marshal(notif)
		var result NotificationData
		json.Unmarshal(data, &result)
	}
}

// BenchmarkChatMessageProcessing 基准测试聊天消息处理
func BenchmarkChatMessageProcessing(b *testing.B) {
	pool := NewConnectionPool()
	go pool.Run()

	// 创建 100 个连接
	for i := 0; i < 100; i++ {
		userID := fmt.Sprintf("user_%d", i)
		conn := &websocket.Conn{}
		userConn := NewUserConnection(userID, conn)
		pool.register <- userConn

		go func(uc *UserConnection) {
			for msg := range uc.Send {
				_ = msg
			}
		}(userConn)
	}

	time.Sleep(100 * time.Millisecond)

	b.ResetTimer()

	for i := 0; i < b.N; i++ {
		msg := &WebSocketMessage{
			Type:      "chat",
			Timestamp: time.Now().Unix(),
			UserID:    fmt.Sprintf("user_%d", i%100),
			Data: json.RawMessage(fmt.Sprintf(
				`{"recipient_id": "user_%d", "content": "Hello world %d"}`,
				(i+1)%100, i,
			)),
		}

		pool.broadcast <- msg
	}

	b.StopTimer()
}

// BenchmarkConnectionPoolLookup 基准测试连接池查询性能
func BenchmarkConnectionPoolLookup(b *testing.B) {
	pool := NewConnectionPool()
	go pool.Run()

	// 创建 1000 个连接
	userIDs := make([]string, 1000)
	for i := 0; i < 1000; i++ {
		userID := fmt.Sprintf("user_%d", i)
		userIDs[i] = userID
		conn := &websocket.Conn{}
		userConn := NewUserConnection(userID, conn)
		pool.register <- userConn
	}

	time.Sleep(200 * time.Millisecond)

	b.ResetTimer()

	for i := 0; i < b.N; i++ {
		userID := userIDs[i%1000]
		pool.GetOnlineUsers()
		_ = userID
	}

	b.StopTimer()
}

// BenchmarkMessageQueueThroughput 基准测试消息队列吞吐量
func BenchmarkMessageQueueThroughput(b *testing.B) {
	queue := make(chan *WebSocketMessage, 1000)

	msg := &WebSocketMessage{
		Type:      "test",
		Timestamp: time.Now().Unix(),
		UserID:    "user_123",
		Data:      []byte(`{"test": "data"}`),
	}

	go func() {
		for msg := range queue {
			_ = msg
		}
	}()

	b.ResetTimer()

	for i := 0; i < b.N; i++ {
		select {
		case queue <- msg:
		default:
		}
	}

	b.StopTimer()
	close(queue)
}

// BenchmarkMemoryUsage 基准测试内存使用
func BenchmarkMemoryUsage(b *testing.B) {
	pool := NewConnectionPool()
	go pool.Run()

	b.ReportAllocs()
	b.ResetTimer()

	for i := 0; i < b.N; i++ {
		userID := fmt.Sprintf("user_%d", i)
		conn := &websocket.Conn{}
		userConn := NewUserConnection(userID, conn)
		pool.register <- userConn
	}

	b.StopTimer()
}

// TestWebSocketPerformance 集成性能测试
func TestWebSocketPerformance(t *testing.T) {
	pool := NewConnectionPool()
	go pool.Run()

	// 创建 10,000 个连接并测试性能
	start := time.Now()

	for i := 0; i < 10000; i++ {
		userID := fmt.Sprintf("user_%d", i)
		conn := &websocket.Conn{}
		userConn := NewUserConnection(userID, conn)
		pool.register <- userConn

		if (i + 1) % 1000 == 0 {
			go func(uc *UserConnection) {
				for msg := range uc.Send {
					_ = msg
				}
			}(userConn)
		}
	}

	time.Sleep(500 * time.Millisecond)

	elapsed := time.Since(start)
	t.Logf("创建 10,000 个连接耗时: %v (%.2f ms/conn)", elapsed, float64(elapsed.Milliseconds())/10000)

	// 测试广播性能
	start = time.Now()

	msg := &WebSocketMessage{
		Type:      "broadcast",
		Timestamp: time.Now().Unix(),
		UserID:    "system",
		Data:      []byte(`{"test": "data"}`),
	}

	for i := 0; i < 100; i++ {
		pool.broadcast <- msg
	}

	time.Sleep(100 * time.Millisecond)

	elapsed = time.Since(start)
	t.Logf("发送 100 条广播消息耗时: %v", elapsed)

	// 测试查询性能
	start = time.Now()

	for i := 0; i < 10000; i++ {
		pool.GetOnlineUsers()
	}

	elapsed = time.Since(start)
	t.Logf("执行 10,000 次查询耗时: %v (%.3f ms/query)", elapsed, float64(elapsed.Microseconds())/10000)

	connCount := pool.GetConnectionCount()
	t.Logf("最终连接数: %d", connCount)
}
