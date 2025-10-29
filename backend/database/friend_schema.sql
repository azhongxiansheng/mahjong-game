-- ===========================================
-- 好友系统数据库架构
-- ===========================================

-- 好友关系表
CREATE TABLE IF NOT EXISTS friends (
  id INT AUTO_INCREMENT PRIMARY KEY,
  player_id VARCHAR(50) NOT NULL,
  friend_id VARCHAR(50) NOT NULL,
  relationship VARCHAR(20) NOT NULL DEFAULT 'friend', -- friend, pending, blocked
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL,
  
  -- 唯一约束：每对玩家之间只能有一种关系
  UNIQUE KEY unique_friendship (player_id, friend_id),
  
  -- 索引优化
  INDEX idx_player_id (player_id),
  INDEX idx_friend_id (friend_id),
  INDEX idx_relationship (relationship),
  INDEX idx_created_at (created_at),
  INDEX idx_status_player (player_id, relationship),
  
  FOREIGN KEY (player_id) REFERENCES players(player_id) ON DELETE CASCADE,
  FOREIGN KEY (friend_id) REFERENCES players(player_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 好友请求表
CREATE TABLE IF NOT EXISTS friend_requests (
  id INT AUTO_INCREMENT PRIMARY KEY,
  from_player_id VARCHAR(50) NOT NULL,
  to_player_id VARCHAR(50) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'pending', -- pending, accepted, rejected
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL,
  
  -- 唯一约束：防止重复请求
  UNIQUE KEY unique_request (from_player_id, to_player_id),
  
  -- 索引优化
  INDEX idx_from_player (from_player_id),
  INDEX idx_to_player (to_player_id),
  INDEX idx_status (status),
  INDEX idx_created_at (created_at),
  INDEX idx_to_player_status (to_player_id, status),
  
  FOREIGN KEY (from_player_id) REFERENCES players(player_id) ON DELETE CASCADE,
  FOREIGN KEY (to_player_id) REFERENCES players(player_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 好友历史记录表（用于统计和分析）
CREATE TABLE IF NOT EXISTS friend_history (
  id INT AUTO_INCREMENT PRIMARY KEY,
  player_id VARCHAR(50) NOT NULL,
  friend_id VARCHAR(50) NOT NULL,
  action VARCHAR(20) NOT NULL, -- added, removed, blocked, unblocked
  action_time BIGINT NOT NULL,
  reason VARCHAR(255),
  
  -- 索引优化
  INDEX idx_player_id (player_id),
  INDEX idx_action (action),
  INDEX idx_action_time (action_time),
  INDEX idx_player_time (player_id, action_time),
  
  FOREIGN KEY (player_id) REFERENCES players(player_id) ON DELETE CASCADE,
  FOREIGN KEY (friend_id) REFERENCES players(player_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ===========================================
-- 数据库视图（用于复杂查询）
-- ===========================================

-- 好友列表视图（包含详细信息）
CREATE OR REPLACE VIEW friend_list_view AS
SELECT 
  f.player_id,
  f.friend_id,
  p.player_name,
  p.avatar,
  p.status,
  p.level,
  p.rating,
  p.wins,
  p.losses,
  p.last_seen,
  f.created_at,
  CASE 
    WHEN p.wins + p.losses > 0 
    THEN ROUND(p.wins / (p.wins + p.losses), 2)
    ELSE 0
  END AS win_rate
FROM friends f
JOIN players p ON f.friend_id = p.player_id
WHERE f.relationship = 'friend';

-- 在线好友视图
CREATE OR REPLACE VIEW online_friend_view AS
SELECT 
  f.player_id,
  f.friend_id,
  p.player_name,
  p.status,
  p.level,
  p.rating,
  p.last_seen,
  f.created_at
FROM friends f
JOIN players p ON f.friend_id = p.player_id
WHERE f.relationship = 'friend' AND (p.status = 'online' OR p.status = 'playing');

-- 待确认请求视图
CREATE OR REPLACE VIEW pending_request_view AS
SELECT 
  fr.id,
  fr.from_player_id,
  p1.player_name AS from_player_name,
  fr.to_player_id,
  p2.player_name AS to_player_name,
  fr.created_at
FROM friend_requests fr
JOIN players p1 ON fr.from_player_id = p1.player_id
JOIN players p2 ON fr.to_player_id = p2.player_id
WHERE fr.status = 'pending';

-- ===========================================
-- 初始化数据（可选）
-- ===========================================

-- 如果需要测试数据，可以插入以下记录

-- 插入示例好友关系
INSERT IGNORE INTO friends (player_id, friend_id, relationship, created_at, updated_at)
VALUES 
  ('player_001', 'player_002', 'friend', UNIX_TIMESTAMP(), UNIX_TIMESTAMP()),
  ('player_002', 'player_001', 'friend', UNIX_TIMESTAMP(), UNIX_TIMESTAMP()),
  ('player_001', 'player_003', 'friend', UNIX_TIMESTAMP(), UNIX_TIMESTAMP()),
  ('player_003', 'player_001', 'friend', UNIX_TIMESTAMP(), UNIX_TIMESTAMP());

-- 插入示例好友请求
INSERT IGNORE INTO friend_requests (from_player_id, to_player_id, status, created_at, updated_at)
VALUES 
  ('player_004', 'player_001', 'pending', UNIX_TIMESTAMP(), UNIX_TIMESTAMP()),
  ('player_005', 'player_002', 'pending', UNIX_TIMESTAMP(), UNIX_TIMESTAMP());
