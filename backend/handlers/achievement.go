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

// ============ 数据结构 ============

type Achievement struct {
	ID            string    `json:"id"`
	Name          string    `json:"name"`
	Description   string    `json:"description"`
	Category      string    `json:"category"`      // progress/oneshot/hidden/seasonal
	Rarity        string    `json:"rarity"`        // common/uncommon/rare/epic/legendary
	MaxProgress   int       `json:"max_progress"`
	RewardPoints  int       `json:"reward_points"`
	RewardCoin    int       `json:"reward_coin"`
	CreatedAt     int64     `json:"created_at"`
}

type PlayerAchievement struct {
	AchievementID string    `json:"achievement_id"`
	PlayerID      string    `json:"player_id"`
	IsUnlocked    bool      `json:"is_unlocked"`
	Progress      int       `json:"progress"`
	UnlockDate    *int64    `json:"unlock_date"`
	CreatedAt     int64     `json:"created_at"`
	UpdatedAt     int64     `json:"updated_at"`
}

type AchievementStats struct {
	TotalAchievements int     `json:"total_achievements"`
	UnlockedCount     int     `json:"unlocked_count"`
	TotalPoints       int     `json:"total_points"`
	CompletionPercent float64 `json:"completion_percent"`
}

type UnlockRequest struct {
	PlayerID      string `json:"player_id" binding:"required"`
	AchievementID string `json:"achievement_id" binding:"required"`
}

type UpdateProgressRequest struct {
	PlayerID      string `json:"player_id" binding:"required"`
	AchievementID string `json:"achievement_id" binding:"required"`
	Progress      int    `json:"progress" binding:"required,min=0"`
}

type GetAchievementsResponse struct {
	Achievements []Achievement `json:"achievements"`
	Total        int           `json:"total"`
}

type GetPlayerAchievementsResponse struct {
	Achievements []PlayerAchievement `json:"achievements"`
	Stats        AchievementStats    `json:"stats"`
}

// ============ API 处理函数 ============

// GetAchievements 获取所有成就定义
// GET /api/achievement/list
func GetAchievements(c *gin.Context) {
	db := c.MustGet("db").(*sql.DB)

	// 获取分页参数
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "100"))

	if page < 1 {
		page = 1
	}
	if limit < 1 || limit > 100 {
		limit = 100
	}

	offset := (page - 1) * limit

	// 查询成就
	rows, err := db.Query(`
		SELECT id, name, description, category, rarity, max_progress, reward_points, reward_coin, created_at
		FROM achievement_definitions
		ORDER BY created_at DESC
		LIMIT ? OFFSET ?
	`, limit, offset)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "数据库查询失败"})
		return
	}
	defer rows.Close()

	achievements := []Achievement{}
	for rows.Next() {
		var achievement Achievement
		if err := rows.Scan(
			&achievement.ID,
			&achievement.Name,
			&achievement.Description,
			&achievement.Category,
			&achievement.Rarity,
			&achievement.MaxProgress,
			&achievement.RewardPoints,
			&achievement.RewardCoin,
			&achievement.CreatedAt,
		); err != nil {
			continue
		}
		achievements = append(achievements, achievement)
	}

	// 获取总数
	var total int
	err = db.QueryRow(`SELECT COUNT(*) FROM achievement_definitions`).Scan(&total)
	if err != nil {
		total = len(achievements)
	}

	c.JSON(http.StatusOK, GetAchievementsResponse{
		Achievements: achievements,
		Total:        total,
	})
}

// GetPlayerAchievements 获取玩家成就进度
// GET /api/achievement/player/:player_id
func GetPlayerAchievements(c *gin.Context) {
	db := c.MustGet("db").(*sql.DB)
	playerID := c.Param("player_id")

	if playerID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "缺少player_id参数"})
		return
	}

	// 获取玩家的所有成就进度
	rows, err := db.Query(`
		SELECT achievement_id, player_id, is_unlocked, progress, unlock_date, created_at, updated_at
		FROM player_achievements
		WHERE player_id = ?
		ORDER BY updated_at DESC
	`, playerID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "数据库查询失败"})
		return
	}
	defer rows.Close()

	playerAchievements := []PlayerAchievement{}
	totalPoints := 0
	unlockedCount := 0

	for rows.Next() {
		var pa PlayerAchievement
		if err := rows.Scan(
			&pa.AchievementID,
			&pa.PlayerID,
			&pa.IsUnlocked,
			&pa.Progress,
			&pa.UnlockDate,
			&pa.CreatedAt,
			&pa.UpdatedAt,
		); err != nil {
			continue
		}

		playerAchievements = append(playerAchievements, pa)

		if pa.IsUnlocked {
			unlockedCount++
			// 获取奖励点数
			var rewardPoints int
			db.QueryRow(`SELECT reward_points FROM achievement_definitions WHERE id = ?`, pa.AchievementID).Scan(&rewardPoints)
			totalPoints += rewardPoints
		}
	}

	// 计算完成度
	var totalAchievements int
	db.QueryRow(`SELECT COUNT(*) FROM achievement_definitions`).Scan(&totalAchievements)

	completionPercent := 0.0
	if totalAchievements > 0 {
		completionPercent = float64(unlockedCount) / float64(totalAchievements)
	}

	stats := AchievementStats{
		TotalAchievements: totalAchievements,
		UnlockedCount:     unlockedCount,
		TotalPoints:       totalPoints,
		CompletionPercent: completionPercent,
	}

	c.JSON(http.StatusOK, GetPlayerAchievementsResponse{
		Achievements: playerAchievements,
		Stats:        stats,
	})
}

// UnlockAchievement 解锁成就
// POST /api/achievement/unlock
func UnlockAchievement(c *gin.Context) {
	db := c.MustGet("db").(*sql.DB)

	var req UnlockRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求格式错误: " + err.Error()})
		return
	}

	// 验证参数
	if req.PlayerID == "" || req.AchievementID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "缺少必要参数"})
		return
	}

	// 检查成就是否存在
	var achievementID string
	err := db.QueryRow(`SELECT id FROM achievement_definitions WHERE id = ?`, req.AchievementID).Scan(&achievementID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "成就不存在"})
		return
	}

	// 插入或更新玩家成就
	now := time.Now().Unix()
	unlockTime := now

	result, err := db.Exec(`
		INSERT INTO player_achievements (player_id, achievement_id, is_unlocked, progress, unlock_date, created_at, updated_at)
		VALUES (?, ?, true, 1, ?, ?, ?)
		ON DUPLICATE KEY UPDATE is_unlocked = true, unlock_date = ?, updated_at = ?
	`, req.PlayerID, req.AchievementID, unlockTime, now, now, unlockTime, now)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "解锁失败: " + err.Error()})
		return
	}

	// 记录到历史表
	db.Exec(`
		INSERT INTO achievement_history (player_id, achievement_id, unlock_date, created_at)
		SELECT ?, ?, ?, ?
		WHERE NOT EXISTS (
			SELECT 1 FROM achievement_history
			WHERE player_id = ? AND achievement_id = ?
		)
	`, req.PlayerID, req.AchievementID, now, now, req.PlayerID, req.AchievementID)

	rowsAffected, _ := result.RowsAffected()

	c.JSON(http.StatusOK, gin.H{
		"success": rowsAffected > 0,
		"message": "成就已解锁",
		"data": gin.H{
			"player_id":      req.PlayerID,
			"achievement_id": req.AchievementID,
			"unlock_date":    unlockTime,
		},
	})
}

// UpdateAchievementProgress 更新成就进度
// POST /api/achievement/progress
func UpdateAchievementProgress(c *gin.Context) {
	db := c.MustGet("db").(*sql.DB)

	var req UpdateProgressRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求格式错误: " + err.Error()})
		return
	}

	// 验证参数
	if req.PlayerID == "" || req.AchievementID == "" || req.Progress < 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数无效"})
		return
	}

	// 获取成就的最大进度
	var maxProgress int
	err := db.QueryRow(`SELECT max_progress FROM achievement_definitions WHERE id = ?`, req.AchievementID).Scan(&maxProgress)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "成就不存在"})
		return
	}

	// 限制进度不超过最大值
	progress := req.Progress
	if progress > maxProgress {
		progress = maxProgress
	}

	// 确定是否解锁
	isUnlocked := progress >= maxProgress
	now := time.Now().Unix()
	var unlockDate interface{} = nil

	if isUnlocked {
		unlockDate = now
	}

	// 更新或插入进度
	result, err := db.Exec(`
		INSERT INTO player_achievements (player_id, achievement_id, is_unlocked, progress, unlock_date, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?)
		ON DUPLICATE KEY UPDATE progress = ?, is_unlocked = ?, unlock_date = ?, updated_at = ?
	`, req.PlayerID, req.AchievementID, isUnlocked, progress, unlockDate, now, now,
		progress, isUnlocked, unlockDate, now)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "更新失败: " + err.Error()})
		return
	}

	// 如果刚解锁，记录到历史表
	if isUnlocked {
		db.Exec(`
			INSERT INTO achievement_history (player_id, achievement_id, unlock_date, created_at)
			SELECT ?, ?, ?, ?
			WHERE NOT EXISTS (
				SELECT 1 FROM achievement_history
				WHERE player_id = ? AND achievement_id = ?
			)
		`, req.PlayerID, req.AchievementID, now, now, req.PlayerID, req.AchievementID)
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "进度已更新",
		"data": gin.H{
			"player_id":      req.PlayerID,
			"achievement_id": req.AchievementID,
			"progress":       progress,
			"is_unlocked":    isUnlocked,
		},
	})
}

// GetAchievementStats 获取成就统计
// GET /api/achievement/stats/:player_id
func GetAchievementStats(c *gin.Context) {
	db := c.MustGet("db").(*sql.DB)
	playerID := c.Param("player_id")

	if playerID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "缺少player_id参数"})
		return
	}

	var totalAchievements, unlockedCount, totalPoints int

	// 获取总成就数
	db.QueryRow(`SELECT COUNT(*) FROM achievement_definitions`).Scan(&totalAchievements)

	// 获取玩家已解锁的成就数
	db.QueryRow(`
		SELECT COUNT(*) FROM player_achievements
		WHERE player_id = ? AND is_unlocked = true
	`, playerID).Scan(&unlockedCount)

	// 计算总点数
	db.QueryRow(`
		SELECT COALESCE(SUM(ad.reward_points), 0)
		FROM player_achievements pa
		JOIN achievement_definitions ad ON pa.achievement_id = ad.id
		WHERE pa.player_id = ? AND pa.is_unlocked = true
	`, playerID).Scan(&totalPoints)

	completionPercent := 0.0
	if totalAchievements > 0 {
		completionPercent = float64(unlockedCount) / float64(totalAchievements) * 100
	}

	c.JSON(http.StatusOK, AchievementStats{
		TotalAchievements: totalAchievements,
		UnlockedCount:     unlockedCount,
		TotalPoints:       totalPoints,
		CompletionPercent: completionPercent,
	})
}

// ExportAchievements 导出成就数据为JSON
// GET /api/achievement/export/:player_id
func ExportAchievements(c *gin.Context) {
	db := c.MustGet("db").(*sql.DB)
	playerID := c.Param("player_id")

	if playerID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "缺少player_id参数"})
		return
	}

	// 查询玩家的所有成就数据
	rows, err := db.Query(`
		SELECT achievement_id, player_id, is_unlocked, progress, unlock_date, created_at, updated_at
		FROM player_achievements
		WHERE player_id = ?
		ORDER BY updated_at DESC
	`, playerID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "数据库查询失败"})
		return
	}
	defer rows.Close()

	achievements := []PlayerAchievement{}
	for rows.Next() {
		var pa PlayerAchievement
		if err := rows.Scan(
			&pa.AchievementID,
			&pa.PlayerID,
			&pa.IsUnlocked,
			&pa.Progress,
			&pa.UnlockDate,
			&pa.CreatedAt,
			&pa.UpdatedAt,
		); err != nil {
			continue
		}
		achievements = append(achievements, pa)
	}

	// 导出为JSON
	data := gin.H{
		"player_id":     playerID,
		"achievements":  achievements,
		"export_time":   time.Now().Unix(),
		"total_count":   len(achievements),
	}

	c.JSON(http.StatusOK, data)
}

// ============ 初始化路由 ============

// InitAchievementHandlers 初始化成就相关的路由
func InitAchievementHandlers(router *gin.Engine) {
	achievementGroup := router.Group("/api/achievement")
	{
		achievementGroup.GET("/list", GetAchievements)
		achievementGroup.GET("/player/:player_id", GetPlayerAchievements)
		achievementGroup.POST("/unlock", UnlockAchievement)
		achievementGroup.POST("/progress", UpdateAchievementProgress)
		achievementGroup.GET("/stats/:player_id", GetAchievementStats)
		achievementGroup.GET("/export/:player_id", ExportAchievements)
	}

	fmt.Println("[Achievement] API routes initialized successfully")
}
