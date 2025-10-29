package main

import (
	"encoding/json"
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

// WebSocketMessage 定义 WebSocket 消息格式
type WebSocketMessage struct {
	Type      string          `json:"type"`
	Timestamp int64           `json:"timestamp"`
	UserID    string          `json:"user_id"`
	Data      json.RawMessage `json:"data"`
}

// ConnectionPool 管理所有 WebSocket 连接
type ConnectionPool struct {
	connections map[string]*UserConnection // user_id -> connection
	mu          sync.RWMutex
	broadcast   chan *WebSocketMessage
	register    chan *UserConnection
	unregister  chan string // user_id
}

// UserConnection 代表单个用户的连接
type UserConnection struct {
	UserID    string
	Conn      *websocket.Conn
	Send      chan *WebSocketMessage
	LastPong  time.Time
	mu        sync.Mutex
}

// NewConnectionPool 创建连接池
func NewConnectionPool() *ConnectionPool {
	return &ConnectionPool{
		connections: make(map[string]*UserConnection),
		broadcast:   make(chan *WebSocketMessage, 256),
		register:    make(chan *UserConnection),
		unregister:  make(chan string),
	}
}

// Run 启动连接池管理协程
func (cp *ConnectionPool) Run() {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case conn := <-cp.register:
			cp.mu.Lock()
			cp.connections[conn.UserID] = conn
			cp.mu.Unlock()
			log.Printf("[WebSocket] 用户 %s 已连接 (总连接数: %d)", conn.UserID, len(cp.connections))

		case userID := <-cp.unregister:
			cp.mu.Lock()
			if conn, ok := cp.connections[userID]; ok {
				delete(cp.connections, userID)
				close(conn.Send)
			}
			cp.mu.Unlock()
			log.Printf("[WebSocket] 用户 %s 已断开 (总连接数: %d)", userID, len(cp.connections))

		case msg := <-cp.broadcast:
			cp.broadcastMessage(msg)

		case <-ticker.C:
			cp.checkConnections()
		}
	}
}

// broadcastMessage 广播消息给所有连接
func (cp *ConnectionPool) broadcastMessage(msg *WebSocketMessage) {
	cp.mu.RLock()
	defer cp.mu.RUnlock()

	for _, conn := range cp.connections {
		select {
		case conn.Send <- msg:
		default:
			// 如果发送通道满，跳过此连接
			log.Printf("[WebSocket] 用户 %s 的发送通道已满，跳过消息", conn.UserID)
		}
	}
}

// SendToUser 发送消息给特定用户
func (cp *ConnectionPool) SendToUser(userID string, msg *WebSocketMessage) error {
	cp.mu.RLock()
	conn, ok := cp.connections[userID]
	cp.mu.RUnlock()

	if !ok {
		return fmt.Errorf("用户 %s 未连接", userID)
	}

	select {
	case conn.Send <- msg:
		return nil
	case <-time.After(5 * time.Second):
		return fmt.Errorf("发送消息超时")
	}
}

// SendToUsers 发送消息给多个用户
func (cp *ConnectionPool) SendToUsers(userIDs []string, msg *WebSocketMessage) map[string]error {
	errors := make(map[string]error)
	for _, userID := range userIDs {
		if err := cp.SendToUser(userID, msg); err != nil {
			errors[userID] = err
		}
	}
	return errors
}

// GetConnectionCount 获取连接数
func (cp *ConnectionPool) GetConnectionCount() int {
	cp.mu.RLock()
	defer cp.mu.RUnlock()
	return len(cp.connections)
}

// GetOnlineUsers 获取在线用户列表
func (cp *ConnectionPool) GetOnlineUsers() []string {
	cp.mu.RLock()
	defer cp.mu.RUnlock()

	users := make([]string, 0, len(cp.connections))
	for userID := range cp.connections {
		users = append(users, userID)
	}
	return users
}

// checkConnections 检查和清理死连接
func (cp *ConnectionPool) checkConnections() {
	cp.mu.Lock()
	defer cp.mu.Unlock()

	now := time.Now()
	for userID, conn := range cp.connections {
		if now.Sub(conn.LastPong) > 60*time.Second {
			log.Printf("[WebSocket] 检测到超时连接，断开用户 %s", userID)
			close(conn.Send)
			delete(cp.connections, userID)
		}
	}
}

// readPump 读取来自客户端的消息
func (uc *UserConnection) readPump(pool *ConnectionPool) {
	defer func() {
		pool.unregister <- uc.UserID
		uc.Conn.Close()
	}()

	uc.Conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	uc.Conn.SetPongHandler(func(string) error {
		uc.mu.Lock()
		uc.LastPong = time.Now()
		uc.mu.Unlock()
		uc.Conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		return nil
	})

	for {
		var msg WebSocketMessage
		err := uc.Conn.ReadJSON(&msg)
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("[WebSocket] 错误: %v", err)
			}
			return
		}

		msg.UserID = uc.UserID
		msg.Timestamp = time.Now().Unix()

		// 路由消息到相应处理器
		routeMessage(&msg, pool)
	}
}

// writePump 写入消息到客户端
func (uc *UserConnection) writePump() {
	ticker := time.NewTicker(54 * time.Second)
	defer func() {
		ticker.Stop()
		uc.Conn.Close()
	}()

	for {
		select {
		case msg, ok := <-uc.Send:
			uc.Conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if !ok {
				uc.Conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			if err := uc.Conn.WriteJSON(msg); err != nil {
				return
			}

		case <-ticker.C:
			uc.Conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := uc.Conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

// routeMessage 路由消息到相应的处理器
func routeMessage(msg *WebSocketMessage, pool *ConnectionPool) {
	switch msg.Type {
	case "ping":
		handlePing(msg, pool)
	case "user_status":
		handleUserStatus(msg, pool)
	case "game_result":
		handleGameResult(msg, pool)
	case "notification":
		handleNotification(msg, pool)
	case "chat":
		handleChat(msg, pool)
	case "team_event":
		handleTeamEvent(msg, pool)
	default:
		log.Printf("[WebSocket] 未知消息类型: %s", msg.Type)
	}
}

// 消息处理器

// handlePing 处理心跳消息
func handlePing(msg *WebSocketMessage, pool *ConnectionPool) {
	response := &WebSocketMessage{
		Type:      "pong",
		Timestamp: time.Now().Unix(),
		UserID:    msg.UserID,
	}

	if err := pool.SendToUser(msg.UserID, response); err != nil {
		log.Printf("[WebSocket] 发送 pong 失败: %v", err)
	}
}

// handleUserStatus 处理用户状态变化
func handleUserStatus(msg *WebSocketMessage, pool *ConnectionPool) {
	type StatusUpdate struct {
		Status string `json:"status"` // online, offline, playing, etc.
	}

	var update StatusUpdate
	if err := json.Unmarshal(msg.Data, &update); err != nil {
		log.Printf("[WebSocket] 解析用户状态失败: %v", err)
		return
	}

	// 广播用户状态给其他用户
	broadcast := &WebSocketMessage{
		Type:      "user_status_changed",
		Timestamp: time.Now().Unix(),
		UserID:    msg.UserID,
		Data:      msg.Data,
	}

	pool.broadcast <- broadcast
	log.Printf("[WebSocket] 用户 %s 状态更新: %s", msg.UserID, update.Status)
}

// handleGameResult 处理游戏结果
func handleGameResult(msg *WebSocketMessage, pool *ConnectionPool) {
	type GameResult struct {
		GameID   string `json:"game_id"`
		Result   string `json:"result"` // win, loss, draw
		Score    int    `json:"score"`
		RoomID   string `json:"room_id"`
	}

	var result GameResult
	if err := json.Unmarshal(msg.Data, &result); err != nil {
		log.Printf("[WebSocket] 解析游戏结果失败: %v", err)
		return
	}

	// 广播游戏结果
	broadcast := &WebSocketMessage{
		Type:      "game_result_update",
		Timestamp: time.Now().Unix(),
		UserID:    msg.UserID,
		Data:      msg.Data,
	}

	pool.broadcast <- broadcast
	log.Printf("[WebSocket] 游戏结果: 用户 %s, 游戏 %s, 结果 %s", msg.UserID, result.GameID, result.Result)
}

// handleNotification 处理通知
func handleNotification(msg *WebSocketMessage, pool *ConnectionPool) {
	type Notification struct {
		RecipientID string `json:"recipient_id"`
		Title       string `json:"title"`
		Content     string `json:"content"`
	}

	var notif Notification
	if err := json.Unmarshal(msg.Data, &notif); err != nil {
		log.Printf("[WebSocket] 解析通知失败: %v", err)
		return
	}

	// 发送通知给指定用户
	if err := pool.SendToUser(notif.RecipientID, msg); err != nil {
		log.Printf("[WebSocket] 发送通知失败: %v", err)
	}
}

// handleChat 处理聊天消息
func handleChat(msg *WebSocketMessage, pool *ConnectionPool) {
	type ChatMsg struct {
		RecipientID string `json:"recipient_id"`
		Content     string `json:"content"`
	}

	var chat ChatMsg
	if err := json.Unmarshal(msg.Data, &chat); err != nil {
		log.Printf("[WebSocket] 解析聊天消息失败: %v", err)
		return
	}

	// 发送聊天消息给收信人
	if err := pool.SendToUser(chat.RecipientID, msg); err != nil {
		log.Printf("[WebSocket] 发送聊天消息失败: %v", err)
	}
}

// handleTeamEvent 处理战队事件
func handleTeamEvent(msg *WebSocketMessage, pool *ConnectionPool) {
	type TeamEvent struct {
		TeamID    string   `json:"team_id"`
		EventType string   `json:"event_type"` // member_joined, member_left, etc.
		UserIDs   []string `json:"user_ids"`   // 相关用户
	}

	var event TeamEvent
	if err := json.Unmarshal(msg.Data, &event); err != nil {
		log.Printf("[WebSocket] 解析战队事件失败: %v", err)
		return
	}

	// 广播战队事件给相关用户
	errors := pool.SendToUsers(event.UserIDs, msg)
	if len(errors) > 0 {
		log.Printf("[WebSocket] 某些用户接收战队事件失败: %v", errors)
	}
}

// NewUserConnection 创建新的用户连接
func NewUserConnection(userID string, conn *websocket.Conn) *UserConnection {
	return &UserConnection{
		UserID:   userID,
		Conn:     conn,
		Send:     make(chan *WebSocketMessage, 256),
		LastPong: time.Now(),
	}
}

// HandleWebSocketConnection WebSocket 连接处理器
func HandleWebSocketConnection(userID string, conn *websocket.Conn, pool *ConnectionPool) {
	uc := NewUserConnection(userID, conn)
	pool.register <- uc

	go uc.readPump(pool)
	go uc.writePump()
}
