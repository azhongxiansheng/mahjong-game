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

// LeaderboardEntry 排行榜条目数据结构
type LeaderboardEntry struct {
	Rank        int     `json:"rank"`
	PlayerID    string  `json:"player_id"`
	PlayerName  string  `json:"player_name"`
	Avatar      string  `json:"avatar"`
	Score       int     `json:"score"`
	Wins        int     `json:"wins"`
	Losses      int     `json:"losses"`
	Games       int     `json:"games"`
	WinRate     float64 `json:"win_rate"`
	Rating      int     `json:"rating"`
	LastUpdate  int64   `json:"last_update"`
}

// LeaderboardType 排行榜类型
type LeaderboardType int

const (
	DAILY    LeaderboardType = 0
	WEEKLY   LeaderboardType = 1
	MONTHLY  LeaderboardType = 2
	SEASONAL LeaderboardType = 3
	GLOBAL   LeaderboardType = 4
)

var leaderboardTypeNames = map[LeaderboardType]string{
	DAILY:    "日排行",
	WEEKLY:   "周排行",
	MONTHLY:  "月排行",
	SEASONAL: "赛季排行",
	GLOBAL:   "全局排行",
}

// GetLeaderboard 获取排行榜数据
// GET /api/leaderboard?type=0&limit=100
func GetLeaderboard(c *gin.Context) {
	db := c.MustGet("db").(*sql.DB)

	// 获取参数
	typeParam := c.DefaultQuery("type", "4")
	limitParam := c.DefaultQuery("limit", "100")

	leaderboardType, err := strconv.Atoi(typeParam)
	if err != nil || leaderboardType < 0 || leaderboardType > 4 {
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false,
			"message": "Invalid leaderboard type",
		})
		return
	}

	limit, err := strconv.Atoi(limitParam)
	if err != nil || limit <= 0 || limit > 1000 {
		limit = 100
	}

	// 查询排行榜数据
	query := `
		SELECT 
			player_id, player_name, avatar,
			score, wins, losses, games, win_rate,
			rating, last_update
		FROM leaderboard
		WHERE leaderboard_type = ?
		ORDER BY rating DESC
		LIMIT ?
	`

	rows, err := db.Query(query, leaderboardType, limit)
	if err != nil {
		fmt.Printf("❌ 数据库查询错误: %v\n", err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"message": "Database query failed",
		})
		return
	}
	defer rows.Close()

	// 构建结果
	entries := []LeaderboardEntry{}
	rank := 1

	for rows.Next() {
		var entry LeaderboardEntry
		err := rows.Scan(
			&entry.PlayerID, &entry.PlayerName, &entry.Avatar,
			&entry.Score, &entry.Wins, &entry.Losses, &entry.Games, &entry.WinRate,
			&entry.Rating, &entry.LastUpdate,
		)
		if err != nil {
			fmt.Printf("❌ 行扫描错误: %v\n", err)
			continue
		}

		entry.Rank = rank
		entries = append(entries, entry)
		rank++
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"type":    leaderboardTypeNames[LeaderboardType(leaderboardType)],
		"count":   len(entries),
		"data":    entries,
	})
}

// GetPlayerRank 获取玩家排名
// GET /api/leaderboard/rank/:player_id?type=4
func GetPlayerRank(c *gin.Context) {
	db := c.MustGet("db").(*sql.DB)

	playerID := c.Param("player_id")
	leaderboardType := c.DefaultQuery("type", "4")

	// 查询玩家排名
	query := `
		SELECT COUNT(*) as rank
		FROM leaderboard
		WHERE leaderboard_type = ? AND rating > (
			SELECT rating FROM leaderboard WHERE player_id = ? AND leaderboard_type = ?
		)
	`

	var rank int
	err := db.QueryRow(query, leaderboardType, playerID, leaderboardType).Scan(&rank)
	if err != nil {
		fmt.Printf("❌ 排名查询错误: %v\n", err)
		c.JSON(http.StatusNotFound, gin.H{
			"success": false,
			"message": "Player not found",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"player_id": playerID,
		"rank": rank + 1,
	})
}

// UpdatePlayerStats 更新玩家统计
// POST /api/leaderboard/update
func UpdatePlayerStats(c *gin.Context) {
	db := c.MustGet("db").(*sql.DB)

	// 解析请求体
	var request struct {
		PlayerID      string `json:"player_id"`
		PlayerName    string `json:"player_name"`
		Avatar        string `json:"avatar"`
		Score         int    `json:"score"`
		Wins          int    `json:"wins"`
		Losses        int    `json:"losses"`
		RatingChange  int    `json:"rating_change"`
		LeaderboardType int   `json:"leaderboard_type"`
	}

	if err := c.ShouldBindJSON(&request); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false,
			"message": "Invalid request body",
		})
		return
	}

	// 验证必需字段
	if request.PlayerID == "" || request.PlayerName == "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false,
			"message": "Missing required fields",
		})
		return
	}

	now := time.Now().UnixMilli()

	// 获取当前玩家数据
	var currentRating, currentWins, currentLosses int
	query := `
		SELECT COALESCE(rating, 1000), COALESCE(wins, 0), COALESCE(losses, 0)
		FROM leaderboard
		WHERE player_id = ? AND leaderboard_type = ?
	`
	err := db.QueryRow(query, request.PlayerID, request.LeaderboardType).
		Scan(&currentRating, &currentWins, &currentLosses)

	newRating := currentRating + request.RatingChange
	newWins := currentWins + request.Wins
	newLosses := currentLosses + request.Losses
	newGames := newWins + newLosses
	newWinRate := 0.0
	if newGames > 0 {
		newWinRate = float64(newWins) / float64(newGames)
	}

	// 如果玩家不存在，插入；否则更新
	if err == sql.ErrNoRows {
		// 插入新玩家
		insertQuery := `
			INSERT INTO leaderboard 
			(player_id, player_name, avatar, score, wins, losses, games, win_rate, rating, leaderboard_type, last_update)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		`
		_, err := db.Exec(insertQuery,
			request.PlayerID, request.PlayerName, request.Avatar,
			request.Score, request.Wins, request.Losses,
			request.Wins + request.Losses, newWinRate,
			1000 + request.RatingChange, request.LeaderboardType, now,
		)
		if err != nil {
			fmt.Printf("❌ 插入玩家错误: %v\n", err)
			c.JSON(http.StatusInternalServerError, gin.H{
				"success": false,
				"message": "Failed to create player record",
			})
			return
		}
	} else if err == nil {
		// 更新现有玩家
		updateQuery := `
			UPDATE leaderboard
			SET player_name = ?, avatar = ?,
				score = score + ?,
				wins = ?, losses = ?,
				games = ?, win_rate = ?,
				rating = ?,
				last_update = ?
			WHERE player_id = ? AND leaderboard_type = ?
		`
		_, err := db.Exec(updateQuery,
			request.PlayerName, request.Avatar,
			request.Score,
			newWins, newLosses,
			newGames, newWinRate,
			newRating,
			now,
			request.PlayerID, request.LeaderboardType,
		)
		if err != nil {
			fmt.Printf("❌ 更新玩家错误: %v\n", err)
			c.JSON(http.StatusInternalServerError, gin.H{
				"success": false,
				"message": "Failed to update player record",
			})
			return
		}
	} else {
		fmt.Printf("❌ 查询错误: %v\n", err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"message": "Database error",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Player stats updated",
		"new_rating": newRating,
		"new_wins": newWins,
		"new_losses": newLosses,
		"win_rate": newWinRate,
	})
}

// GetLeaderboardStats 获取排行榜统计
// GET /api/leaderboard/stats?type=4
func GetLeaderboardStats(c *gin.Context) {
	db := c.MustGet("db").(*sql.DB)

	leaderboardType := c.DefaultQuery("type", "4")

	query := `
		SELECT 
			COUNT(*) as total_players,
			AVG(rating) as avg_rating,
			MAX(rating) as max_rating,
			MIN(rating) as min_rating
		FROM leaderboard
		WHERE leaderboard_type = ?
	`

	var stats struct {
		TotalPlayers int     `json:"total_players"`
		AvgRating    float64 `json:"avg_rating"`
		MaxRating    int     `json:"max_rating"`
		MinRating    int     `json:"min_rating"`
	}

	err := db.QueryRow(query, leaderboardType).Scan(
		&stats.TotalPlayers,
		&stats.AvgRating,
		&stats.MaxRating,
		&stats.MinRating,
	)

	if err != nil {
		fmt.Printf("❌ 统计查询错误: %v\n", err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"message": "Failed to get statistics",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data": stats,
	})
}

// ExportLeaderboard 导出排行榜为 JSON
// GET /api/leaderboard/export?type=4&limit=100
func ExportLeaderboard(c *gin.Context) {
	db := c.MustGet("db").(*sql.DB)

	typeParam := c.DefaultQuery("type", "4")
	limitParam := c.DefaultQuery("limit", "100")

	leaderboardType, _ := strconv.Atoi(typeParam)
	limit, _ := strconv.Atoi(limitParam)

	if limit > 1000 {
		limit = 1000
	}

	// 获取排行榜数据
	query := `
		SELECT 
			player_id, player_name, avatar,
			score, wins, losses, games, win_rate,
			rating, last_update
		FROM leaderboard
		WHERE leaderboard_type = ?
		ORDER BY rating DESC
		LIMIT ?
	`

	rows, err := db.Query(query, leaderboardType, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"message": "Failed to export leaderboard",
		})
		return
	}
	defer rows.Close()

	entries := []LeaderboardEntry{}
	rank := 1

	for rows.Next() {
		var entry LeaderboardEntry
		rows.Scan(
			&entry.PlayerID, &entry.PlayerName, &entry.Avatar,
			&entry.Score, &entry.Wins, &entry.Losses, &entry.Games, &entry.WinRate,
			&entry.Rating, &entry.LastUpdate,
		)
		entry.Rank = rank
		entries = append(entries, entry)
		rank++
	}

	// 返回 JSON 格式
	c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=leaderboard_%d.json", leaderboardType))
	c.Header("Content-Type", "application/json")
	c.JSON(http.StatusOK, entries)
}

// InitLeaderboardHandlers 初始化排行榜路由
func InitLeaderboardHandlers(router *gin.Engine) {
	fmt.Println("✅ 排行榜 API 处理器已初始化")

	api := router.Group("/api/leaderboard")
	{
		// 获取排行榜
		api.GET("", GetLeaderboard)
		fmt.Println("  ✅ GET /api/leaderboard - 获取排行榜")

		// 获取玩家排名
		api.GET("/rank/:player_id", GetPlayerRank)
		fmt.Println("  ✅ GET /api/leaderboard/rank/:player_id - 获取玩家排名")

		// 更新玩家统计
		api.POST("/update", UpdatePlayerStats)
		fmt.Println("  ✅ POST /api/leaderboard/update - 更新玩家统计")

		// 获取排行榜统计
		api.GET("/stats", GetLeaderboardStats)
		fmt.Println("  ✅ GET /api/leaderboard/stats - 获取排行榜统计")

		// 导出排行榜
		api.GET("/export", ExportLeaderboard)
		fmt.Println("  ✅ GET /api/leaderboard/export - 导出排行榜")
	}
}
