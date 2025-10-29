package handlers

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
)

// Friend 好友信息
type Friend struct {
	FriendID   string    `json:"friend_id"`
	FriendName string    `json:"friend_name"`
	Avatar     string    `json:"avatar"`
	Status     string    `json:"status"` // online, offline, playing
	Level      int       `json:"level"`
	Rating     int       `json:"rating"`
	Wins       int       `json:"wins"`
	Losses     int       `json:"losses"`
	CreatedAt  int64     `json:"created_at"`
	LastSeen   int64     `json:"last_seen"`
	Tier       string    `json:"tier"`
	WinRate    float64   `json:"win_rate"`
}

// FriendRequest 好友请求
type FriendRequest struct {
	FromPlayerID   string `json:"from_player_id"`
	FromPlayerName string `json:"from_player_name"`
	CreatedAt      int64  `json:"created_at"`
}

// AddFriendRequest 添加好友请求
type AddFriendRequest struct {
	TargetPlayerID   string `json:"target_player_id" binding:"required"`
	TargetPlayerName string `json:"target_player_name" binding:"required"`
}

// AcceptFriendRequest 接受好友请求
type AcceptFriendRequest struct {
	FromPlayerID string `json:"from_player_id" binding:"required"`
}

// GetFriendsResponse 获取好友响应
type GetFriendsResponse struct {
	Friends []Friend `json:"friends"`
	Total   int      `json:"total"`
}

// FriendStatistics 好友统计
type FriendStatistics struct {
	TotalFriends      int `json:"total_friends"`
	OnlineFriends     int `json:"online_friends"`
	OfflineFriends    int `json:"offline_friends"`
	PlayingFriends    int `json:"playing_friends"`
	BlockedPlayers    int `json:"blocked_players"`
	PendingRequests   int `json:"pending_requests"`
	AverageFriendRating int `json:"average_friend_rating"`
}

// GetFriends 获取好友列表
// GET /api/friend/list?player_id=xxx&limit=50&offset=0
func GetFriends(c *gin.Context) {
	playerID := c.Query("player_id")
	limit := c.DefaultQuery("limit", "50")
	offset := c.DefaultQuery("offset", "0")

	if playerID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "player_id is required"})
		return
	}

	limitInt, err := strconv.Atoi(limit)
	if err != nil || limitInt > 1000 {
		limitInt = 50
	}

	offsetInt, err := strconv.Atoi(offset)
	if err != nil {
		offsetInt = 0
	}

	// 查询好友列表
	rows, err := DB.Query(`
		SELECT f.friend_id, p.player_name, p.avatar, p.status, p.level, p.rating,
		       p.wins, p.losses, f.created_at, p.last_seen
		FROM friends f
		JOIN players p ON f.friend_id = p.player_id
		WHERE f.player_id = ? AND f.relationship = 'friend'
		ORDER BY p.status DESC, f.created_at DESC
		LIMIT ? OFFSET ?
	`, playerID, limitInt, offsetInt)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "database error"})
		return
	}
	defer rows.Close()

	var friends []Friend
	for rows.Next() {
		var f Friend
		var losses, wins int
		err := rows.Scan(&f.FriendID, &f.FriendName, &f.Avatar, &f.Status, &f.Level, &f.Rating,
			&wins, &losses, &f.CreatedAt, &f.LastSeen)
		if err != nil {
			continue
		}
		f.Wins = wins
		f.Losses = losses
		
		// 计算胜率
		total := wins + losses
		if total > 0 {
			f.WinRate = float64(wins) / float64(total)
		}

		friends = append(friends, f)
	}

	c.JSON(http.StatusOK, GetFriendsResponse{
		Friends: friends,
		Total:   len(friends),
	})
}

// GetOnlineFriends 获取在线好友
// GET /api/friend/online?player_id=xxx
func GetOnlineFriends(c *gin.Context) {
	playerID := c.Query("player_id")

	if playerID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "player_id is required"})
		return
	}

	// 查询在线好友
	rows, err := DB.Query(`
		SELECT f.friend_id, p.player_name, p.avatar, p.status, p.level, p.rating,
		       p.wins, p.losses, f.created_at, p.last_seen
		FROM friends f
		JOIN players p ON f.friend_id = p.player_id
		WHERE f.player_id = ? AND f.relationship = 'friend' 
		      AND (p.status = 'online' OR p.status = 'playing')
		ORDER BY p.status DESC, p.last_seen DESC
		LIMIT 100
	`, playerID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "database error"})
		return
	}
	defer rows.Close()

	var friends []Friend
	for rows.Next() {
		var f Friend
		var losses, wins int
		err := rows.Scan(&f.FriendID, &f.FriendName, &f.Avatar, &f.Status, &f.Level, &f.Rating,
			&wins, &losses, &f.CreatedAt, &f.LastSeen)
		if err != nil {
			continue
		}
		f.Wins = wins
		f.Losses = losses
		if (wins + losses) > 0 {
			f.WinRate = float64(wins) / float64(wins+losses)
		}
		friends = append(friends, f)
	}

	c.JSON(http.StatusOK, GetFriendsResponse{
		Friends: friends,
		Total:   len(friends),
	})
}

// SendFriendRequest 发送好友请求
// POST /api/friend/request/send
func SendFriendRequest(c *gin.Context) {
	var req AddFriendRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	playerID := c.GetString("player_id")
	if playerID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "not authenticated"})
		return
	}

	now := time.Now().Unix()

	// 检查是否已是好友
	var exists bool
	err := DB.QueryRow(`
		SELECT COUNT(*) > 0 FROM friends 
		WHERE player_id = ? AND friend_id = ? AND relationship = 'friend'
	`, playerID, req.TargetPlayerID).Scan(&exists)

	if exists {
		c.JSON(http.StatusBadRequest, gin.H{"error": "already friends"})
		return
	}

	// 插入好友请求
	_, err = DB.Exec(`
		INSERT INTO friend_requests (from_player_id, to_player_id, status, created_at)
		VALUES (?, ?, 'pending', ?)
		ON DUPLICATE KEY UPDATE status = 'pending', created_at = ?
	`, playerID, req.TargetPlayerID, now, now)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "database error"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "friend request sent",
		"target_id": req.TargetPlayerID,
	})
}

// AcceptFriendRequest 接受好友请求
// POST /api/friend/request/accept
func AcceptFriendRequestHandler(c *gin.Context) {
	var req AcceptFriendRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	playerID := c.GetString("player_id")
	if playerID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "not authenticated"})
		return
	}

	now := time.Now().Unix()

	// 开启事务
	tx, err := DB.Begin()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "database error"})
		return
	}
	defer tx.Rollback()

	// 添加双向好友关系
	_, err = tx.Exec(`
		INSERT INTO friends (player_id, friend_id, relationship, created_at, updated_at)
		VALUES (?, ?, 'friend', ?, ?)
		ON DUPLICATE KEY UPDATE relationship = 'friend', updated_at = ?
	`, playerID, req.FromPlayerID, now, now, now)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "database error"})
		return
	}

	_, err = tx.Exec(`
		INSERT INTO friends (player_id, friend_id, relationship, created_at, updated_at)
		VALUES (?, ?, 'friend', ?, ?)
		ON DUPLICATE KEY UPDATE relationship = 'friend', updated_at = ?
	`, req.FromPlayerID, playerID, now, now, now)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "database error"})
		return
	}

	// 更新请求状态
	_, err = tx.Exec(`
		UPDATE friend_requests SET status = 'accepted', updated_at = ?
		WHERE from_player_id = ? AND to_player_id = ?
	`, now, req.FromPlayerID, playerID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "database error"})
		return
	}

	tx.Commit()

	c.JSON(http.StatusOK, gin.H{
		"message": "friend request accepted",
		"friend_id": req.FromPlayerID,
	})
}

// RemoveFriend 删除好友
// POST /api/friend/remove
func RemoveFriend(c *gin.Context) {
	type RemoveRequest struct {
		FriendID string `json:"friend_id" binding:"required"`
	}

	var req RemoveRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	playerID := c.GetString("player_id")
	if playerID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "not authenticated"})
		return
	}

	now := time.Now().Unix()

	// 删除双向好友关系
	_, err := DB.Exec(`
		DELETE FROM friends 
		WHERE (player_id = ? AND friend_id = ?) OR (player_id = ? AND friend_id = ?)
	`, playerID, req.FriendID, req.FriendID, playerID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "database error"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "friend removed",
		"friend_id": req.FriendID,
	})
}

// BlockPlayer 屏蔽玩家
// POST /api/friend/block
func BlockPlayer(c *gin.Context) {
	type BlockRequest struct {
		PlayerID   string `json:"player_id" binding:"required"`
		PlayerName string `json:"player_name" binding:"required"`
	}

	var req BlockRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	playerID := c.GetString("player_id")
	if playerID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "not authenticated"})
		return
	}

	now := time.Now().Unix()

	_, err := DB.Exec(`
		INSERT INTO friends (player_id, friend_id, relationship, created_at, updated_at)
		VALUES (?, ?, 'blocked', ?, ?)
		ON DUPLICATE KEY UPDATE relationship = 'blocked', updated_at = ?
	`, playerID, req.PlayerID, now, now, now)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "database error"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "player blocked",
		"player_id": req.PlayerID,
	})
}

// UnblockPlayer 解除屏蔽
// POST /api/friend/unblock
func UnblockPlayer(c *gin.Context) {
	type UnblockRequest struct {
		PlayerID string `json:"player_id" binding:"required"`
	}

	var req UnblockRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	playerID := c.GetString("player_id")
	if playerID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "not authenticated"})
		return
	}

	_, err := DB.Exec(`
		DELETE FROM friends 
		WHERE player_id = ? AND friend_id = ? AND relationship = 'blocked'
	`, playerID, req.PlayerID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "database error"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "player unblocked",
		"player_id": req.PlayerID,
	})
}

// GetFriendStatistics 获取好友统计
// GET /api/friend/stats?player_id=xxx
func GetFriendStatistics(c *gin.Context) {
	playerID := c.Query("player_id")

	if playerID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "player_id is required"})
		return
	}

	stats := FriendStatistics{}

	// 获取好友总数
	DB.QueryRow(`
		SELECT COUNT(*) FROM friends 
		WHERE player_id = ? AND relationship = 'friend'
	`, playerID).Scan(&stats.TotalFriends)

	// 获取在线好友
	DB.QueryRow(`
		SELECT COUNT(*) FROM friends f
		JOIN players p ON f.friend_id = p.player_id
		WHERE f.player_id = ? AND f.relationship = 'friend' 
		      AND (p.status = 'online' OR p.status = 'playing')
	`, playerID).Scan(&stats.OnlineFriends)

	// 获取游戏中好友
	DB.QueryRow(`
		SELECT COUNT(*) FROM friends f
		JOIN players p ON f.friend_id = p.player_id
		WHERE f.player_id = ? AND f.relationship = 'friend' AND p.status = 'playing'
	`, playerID).Scan(&stats.PlayingFriends)

	// 获取离线好友
	stats.OfflineFriends = stats.TotalFriends - stats.OnlineFriends

	// 获取黑名单数
	DB.QueryRow(`
		SELECT COUNT(*) FROM friends 
		WHERE player_id = ? AND relationship = 'blocked'
	`, playerID).Scan(&stats.BlockedPlayers)

	// 获取待确认请求
	DB.QueryRow(`
		SELECT COUNT(*) FROM friend_requests 
		WHERE to_player_id = ? AND status = 'pending'
	`, playerID).Scan(&stats.PendingRequests)

	// 获取平均好友评分
	DB.QueryRow(`
		SELECT COALESCE(AVG(p.rating), 0) FROM friends f
		JOIN players p ON f.friend_id = p.player_id
		WHERE f.player_id = ? AND f.relationship = 'friend'
	`, playerID).Scan(&stats.AverageFriendRating)

	c.JSON(http.StatusOK, stats)
}

// InitFriendHandlers 初始化好友路由
func InitFriendHandlers(router *gin.Engine) {
	friendGroup := router.Group("/api/friend")
	{
		friendGroup.GET("/list", GetFriends)
		friendGroup.GET("/online", GetOnlineFriends)
		friendGroup.GET("/stats", GetFriendStatistics)
		friendGroup.POST("/request/send", SendFriendRequest)
		friendGroup.POST("/request/accept", AcceptFriendRequestHandler)
		friendGroup.POST("/remove", RemoveFriend)
		friendGroup.POST("/block", BlockPlayer)
		friendGroup.POST("/unblock", UnblockPlayer)
	}
}
