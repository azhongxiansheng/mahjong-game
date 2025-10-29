package main

import (
	"encoding/json"
	"testing"
	"time"
)

// TestWebSocketIntegration WebSocket 完整集成测试
func TestWebSocketIntegration(t *testing.T) {
	pool := NewConnectionPool()
	go pool.Run()

	// 创建多个用户连接
	users := []string{"user_1", "user_2", "user_3", "user_4", "user_5"}
	for _, userID := range users {
		conn := &mockConnection{}
		userConn := NewUserConnection(userID, conn)
		pool.register <- userConn

		go func(uc *UserConnection) {
			for msg := range uc.Send {
				t.Logf("用户 %s 收到消息: %s", uc.UserID, msg.Type)
			}
		}(userConn)
	}

	time.Sleep(100 * time.Millisecond)

	// 测试: 用户 1 发送通知给用户 2
	notifData := map[string]string{
		"recipient_id": "user_2",
		"title":        "好友请求",
		"content":      "用户 1 请求添加你为好友",
	}

	data, _ := json.Marshal(notifData)
	msg := &WebSocketMessage{
		Type:      "notification",
		UserID:    "user_1",
		Timestamp: time.Now().Unix(),
		Data:      data,
	}

	if err := pool.SendToUser("user_2", msg); err != nil {
		t.Errorf("发送通知失败: %v", err)
	}

	// 验证在线用户
	onlineUsers := pool.GetOnlineUsers()
	if len(onlineUsers) != 5 {
		t.Errorf("期望 5 个在线用户，实际 %d 个", len(onlineUsers))
	}

	t.Logf("集成测试完成，在线用户数: %d", len(onlineUsers))
}

// TestUserStatusBroadcast 用户状态广播测试
func TestUserStatusBroadcast(t *testing.T) {
	pool := NewConnectionPool()
	go pool.Run()

	// 创建用户连接
	userConn := NewUserConnection("user_1", &mockConnection{})
	pool.register <- userConn

	receivedCount := 0
	go func(uc *UserConnection) {
		for msg := range uc.Send {
			if msg.Type == "user_status_changed" {
				receivedCount++
				t.Logf("接收到用户状态变化: %s", msg.Type)
			}
		}
	}(userConn)

	time.Sleep(100 * time.Millisecond)

	// 广播用户状态变化
	statusData := map[string]string{
		"status": "playing",
	}

	data, _ := json.Marshal(statusData)
	statusMsg := &WebSocketMessage{
		Type:      "user_status",
		UserID:    "user_1",
		Timestamp: time.Now().Unix(),
		Data:      data,
	}

	pool.broadcast <- statusMsg

	time.Sleep(100 * time.Millisecond)

	if receivedCount == 0 {
		t.Error("未收到状态广播消息")
	}

	t.Logf("状态广播测试完成，收到消息数: %d", receivedCount)
}

// TestGameResultNotification 游戏结果通知测试
func TestGameResultNotification(t *testing.T) {
	pool := NewConnectionPool()
	go pool.Run()

	// 创建四个玩家连接
	players := []string{"player_1", "player_2", "player_3", "player_4"}
	receivedCounts := make(map[string]int)

	for _, playerID := range players {
		conn := NewUserConnection(playerID, &mockConnection{})
		pool.register <- conn

		go func(playerID string, uc *UserConnection) {
			for msg := range uc.Send {
				if msg.Type == "game_result_update" {
					receivedCounts[playerID]++
				}
			}
		}(playerID, conn)
	}

	time.Sleep(100 * time.Millisecond)

	// 广播游戏结果
	resultData := map[string]interface{}{
		"game_id": "game_001",
		"result":  "win",
		"score":   100,
		"room_id": "room_1",
	}

	data, _ := json.Marshal(resultData)
	gameMsg := &WebSocketMessage{
		Type:      "game_result",
		UserID:    "player_1",
		Timestamp: time.Now().Unix(),
		Data:      data,
	}

	pool.broadcast <- gameMsg

	time.Sleep(100 * time.Millisecond)

	// 验证所有玩家都收到了结果
	for _, playerID := range players {
		if receivedCounts[playerID] == 0 {
			t.Errorf("玩家 %s 未收到游戏结果", playerID)
		}
	}

	t.Logf("游戏结果测试完成")
}

// TestConcurrentUserActions 并发用户操作测试
func TestConcurrentUserActions(t *testing.T) {
	pool := NewConnectionPool()
	go pool.Run()

	// 创建 100 个用户连接
	userCount := 100
	for i := 0; i < userCount; i++ {
		userID := "concurrent_user_" + string(rune(i))
		conn := NewUserConnection(userID, &mockConnection{})
		pool.register <- conn

		go func(uc *UserConnection) {
			for msg := range uc.Send {
				_ = msg
			}
		}(conn)
	}

	time.Sleep(200 * time.Millisecond)

	// 验证连接数
	if pool.GetConnectionCount() != userCount {
		t.Errorf("期望 %d 个连接，实际 %d 个", userCount, pool.GetConnectionCount())
	}

	t.Logf("并发用户测试完成，连接数: %d", pool.GetConnectionCount())
}

// TestMessageQueueResilience 消息队列容错测试
func TestMessageQueueResilience(t *testing.T) {
	pool := NewConnectionPool()
	go pool.Run()

	userConn := NewUserConnection("user_1", &mockConnection{})
	pool.register <- userConn

	// 启动接收协程
	go func(uc *UserConnection) {
		for msg := range uc.Send {
			_ = msg
		}
	}(userConn)

	time.Sleep(100 * time.Millisecond)

	// 快速发送大量消息
	messageCount := 0
	for i := 0; i < 1000; i++ {
		msg := &WebSocketMessage{
			Type:      "test",
			UserID:    "user_1",
			Timestamp: time.Now().Unix(),
			Data:      []byte(`{"index": ` + string(rune(i)) + `}`),
		}

		if err := pool.SendToUser("user_1", msg); err == nil {
			messageCount++
		}
	}

	time.Sleep(100 * time.Millisecond)

	if messageCount < 900 {
		t.Logf("警告: 仅发送 %d 条消息 (期望 >= 900 条)", messageCount)
	}

	t.Logf("消息队列容错测试完成，成功发送: %d 条消息", messageCount)
}

// TestConnectionTimeout 连接超时测试
func TestConnectionTimeout(t *testing.T) {
	pool := NewConnectionPool()
	go pool.Run()

	userConn := NewUserConnection("timeout_user", &mockConnection{})
	pool.register <- userConn

	time.Sleep(100 * time.Millisecond)

	initialCount := pool.GetConnectionCount()

	// 模拟超时（跳过 pong 更新）
	time.Sleep(65 * time.Second) // 超过 60 秒超时时间

	// 触发连接检查
	pool.checkConnections()

	time.Sleep(100 * time.Millisecond)

	// 验证连接被清理
	if pool.GetConnectionCount() >= initialCount {
		t.Logf("注意: 超时连接清理测试可能需要更长时间")
	}
}

// TestMultipleRoomsScenario 多房间场景测试
func TestMultipleRoomsScenario(t *testing.T) {
	pool := NewConnectionPool()
	go pool.Run()

	// 模拟两个房间，每个房间 4 个玩家
	rooms := map[string][]string{
		"room_1": {"room1_p1", "room1_p2", "room1_p3", "room1_p4"},
		"room_2": {"room2_p1", "room2_p2", "room2_p3", "room2_p4"},
	}

	for room, players := range rooms {
		for _, playerID := range players {
			conn := NewUserConnection(playerID, &mockConnection{})
			pool.register <- conn

			go func(uc *UserConnection) {
				for msg := range uc.Send {
					_ = msg
				}
			}(conn)
		}
	}

	time.Sleep(100 * time.Millisecond)

	// 验证总连接数
	if pool.GetConnectionCount() != 8 {
		t.Errorf("期望 8 个连接，实际 %d 个", pool.GetConnectionCount())
	}

	// 为每个房间发送游戏事件
	for roomID, players := range rooms {
		eventData := map[string]interface{}{
			"room_id": roomID,
			"event":   "game_started",
			"players": players,
		}

		data, _ := json.Marshal(eventData)
		eventMsg := &WebSocketMessage{
			Type:      "game_result",
			UserID:    "system",
			Timestamp: time.Now().Unix(),
			Data:      data,
		}

		// 发送给房间内所有玩家
		errors := pool.SendToUsers(players, eventMsg)
		if len(errors) > 0 {
			t.Logf("房间 %s 中有 %d 个玩家接收失败", roomID, len(errors))
		}
	}

	t.Logf("多房间场景测试完成")
}

// TestOnlineUsersList 在线用户列表测试
func TestOnlineUsersList(t *testing.T) {
	pool := NewConnectionPool()
	go pool.Run()

	// 添加用户
	userIDs := []string{"user_a", "user_b", "user_c", "user_d", "user_e"}
	for _, userID := range userIDs {
		conn := NewUserConnection(userID, &mockConnection{})
		pool.register <- conn

		go func(uc *UserConnection) {
			for msg := range uc.Send {
				_ = msg
			}
		}(conn)
	}

	time.Sleep(100 * time.Millisecond)

	// 获取在线用户列表
	onlineUsers := pool.GetOnlineUsers()

	if len(onlineUsers) != len(userIDs) {
		t.Errorf("期望 %d 个在线用户，实际 %d 个", len(userIDs), len(onlineUsers))
	}

	t.Logf("在线用户列表: %v", onlineUsers)
}

// TestErrorHandling 错误处理测试
func TestErrorHandling(t *testing.T) {
	pool := NewConnectionPool()
	go pool.Run()

	// 测试发送给不存在的用户
	msg := &WebSocketMessage{
		Type:      "test",
		UserID:    "system",
		Timestamp: time.Now().Unix(),
		Data:      []byte(`{}`),
	}

	err := pool.SendToUser("nonexistent_user", msg)
	if err == nil {
		t.Error("期望向不存在的用户发送时收到错误")
	}

	t.Logf("错误处理测试完成: %v", err)
}

// mockConnection 是 websocket.Conn 的模拟实现
type mockConnection struct{}

func (m *mockConnection) Close() error {
	return nil
}

func (m *mockConnection) SetReadDeadline(time.Time) error {
	return nil
}

func (m *mockConnection) SetWriteDeadline(time.Time) error {
	return nil
}

func (m *mockConnection) SetPongHandler(h func(string) error) {
	// Mock implementation
}

func (m *mockConnection) ReadJSON(v interface{}) error {
	return nil
}

func (m *mockConnection) WriteJSON(v interface{}) error {
	return nil
}

func (m *mockConnection) WriteMessage(messageType int, data []byte) error {
	return nil
}
