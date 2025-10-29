-- ============ 成就系统数据库表 ============

-- 成就定义表 (静态数据)
CREATE TABLE IF NOT EXISTS achievement_definitions (
  id VARCHAR(50) PRIMARY KEY COMMENT '成就ID',
  name VARCHAR(100) NOT NULL COMMENT '成就名称',
  description TEXT COMMENT '成就描述',
  category VARCHAR(20) NOT NULL COMMENT '成就分类 (progress/oneshot/hidden/seasonal)',
  rarity VARCHAR(20) NOT NULL COMMENT '稀有度 (common/uncommon/rare/epic/legendary)',
  max_progress INT DEFAULT 1 COMMENT '最大进度值',
  reward_points INT DEFAULT 100 COMMENT '奖励成就点数',
  reward_coin INT DEFAULT 0 COMMENT '奖励金币',
  created_at BIGINT NOT NULL COMMENT '创建时间戳',
  
  INDEX idx_category (category) COMMENT '按分类查询索引',
  INDEX idx_rarity (rarity) COMMENT '按稀有度查询索引'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='成就定义表';

-- 玩家成就进度表 (动态数据)
CREATE TABLE IF NOT EXISTS player_achievements (
  id INT AUTO_INCREMENT PRIMARY KEY COMMENT '记录ID',
  player_id VARCHAR(50) NOT NULL COMMENT '玩家ID',
  achievement_id VARCHAR(50) NOT NULL COMMENT '成就ID',
  is_unlocked BOOL DEFAULT FALSE COMMENT '是否已解锁',
  progress INT DEFAULT 0 COMMENT '当前进度',
  unlock_date BIGINT COMMENT '解锁时间戳',
  created_at BIGINT NOT NULL COMMENT '创建时间戳',
  updated_at BIGINT NOT NULL COMMENT '更新时间戳',
  
  UNIQUE KEY unique_player_achievement (player_id, achievement_id) COMMENT '玩家-成就唯一索引',
  FOREIGN KEY (achievement_id) REFERENCES achievement_definitions(id) ON DELETE CASCADE,
  
  INDEX idx_player_id (player_id) COMMENT '按玩家查询索引',
  INDEX idx_is_unlocked (is_unlocked) COMMENT '按解锁状态查询索引',
  INDEX idx_updated_at (updated_at) COMMENT '按更新时间排序索引',
  INDEX idx_unlock_date (unlock_date) COMMENT '按解锁时间查询索引'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='玩家成就进度表';

-- 成就历史记录表
CREATE TABLE IF NOT EXISTS achievement_history (
  id INT AUTO_INCREMENT PRIMARY KEY COMMENT '记录ID',
  player_id VARCHAR(50) NOT NULL COMMENT '玩家ID',
  achievement_id VARCHAR(50) NOT NULL COMMENT '成就ID',
  unlock_date BIGINT NOT NULL COMMENT '解锁时间戳',
  created_at BIGINT NOT NULL COMMENT '记录创建时间',
  
  FOREIGN KEY (achievement_id) REFERENCES achievement_definitions(id) ON DELETE CASCADE,
  
  INDEX idx_player_id (player_id) COMMENT '按玩家查询索引',
  INDEX idx_unlock_date (unlock_date) COMMENT '按解锁时间查询索引',
  INDEX idx_created_at (created_at) COMMENT '按创建时间排序索引',
  INDEX idx_player_unlock (player_id, unlock_date) COMMENT '玩家-时间复合索引'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='成就解锁历史表';

-- ============ 初始化数据（示例） ============

-- 插入示例成就定义
INSERT INTO achievement_definitions (id, name, description, category, rarity, max_progress, reward_points, reward_coin, created_at)
VALUES
  ('first_win', '首次胜利', '赢得第一场游戏', 'oneshot', 'common', 1, 100, 50, UNIX_TIMESTAMP()),
  ('10_wins', '十连胜起', '赢得10场游戏', 'progress', 'uncommon', 10, 200, 100, UNIX_TIMESTAMP()),
  ('50_wins', '五十岁了', '赢得50场游戏', 'progress', 'rare', 50, 500, 250, UNIX_TIMESTAMP()),
  ('100_wins', '百战百胜', '赢得100场游戏', 'progress', 'epic', 100, 1000, 500, UNIX_TIMESTAMP()),
  ('win_streak_3', '三连胜', '连续赢得3场', 'progress', 'uncommon', 3, 150, 75, UNIX_TIMESTAMP()),
  ('win_streak_5', '五连胜', '连续赢得5场', 'progress', 'rare', 5, 300, 150, UNIX_TIMESTAMP()),
  ('win_streak_10', '十连胜', '连续赢得10场', 'progress', 'epic', 10, 500, 250, UNIX_TIMESTAMP()),
  ('score_5000', '高手等级', '单局分数达到5000', 'oneshot', 'rare', 1, 300, 150, UNIX_TIMESTAMP()),
  ('score_10000', '超级高手', '单局分数达到10000', 'oneshot', 'epic', 1, 500, 250, UNIX_TIMESTAMP()),
  ('score_20000', '神级玩家', '单局分数达到20000', 'oneshot', 'legendary', 1, 1000, 500, UNIX_TIMESTAMP()),
  ('hidden_1', '隐藏成就1', '完成特殊条件', 'hidden', 'legendary', 1, 2000, 1000, UNIX_TIMESTAMP());

-- ============ 查询示例 ============

-- 查询所有成就
-- SELECT * FROM achievement_definitions ORDER BY created_at DESC;

-- 查询玩家成就进度
-- SELECT * FROM player_achievements WHERE player_id = 'player_123' ORDER BY updated_at DESC;

-- 查询玩家已解锁的成就
-- SELECT pa.*, ad.name, ad.reward_points FROM player_achievements pa
-- JOIN achievement_definitions ad ON pa.achievement_id = ad.id
-- WHERE pa.player_id = 'player_123' AND pa.is_unlocked = TRUE;

-- 查询玩家成就统计
-- SELECT 
--   COUNT(*) as total_achievements,
--   SUM(CASE WHEN is_unlocked THEN 1 ELSE 0 END) as unlocked_count,
--   SUM(CASE WHEN is_unlocked THEN ad.reward_points ELSE 0 END) as total_points
-- FROM player_achievements pa
-- LEFT JOIN achievement_definitions ad ON pa.achievement_id = ad.id
-- WHERE pa.player_id = 'player_123';
