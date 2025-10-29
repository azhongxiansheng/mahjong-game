-- 排行榜数据库表结构
-- 创建排行榜表
CREATE TABLE IF NOT EXISTS leaderboard (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    player_id TEXT NOT NULL,
    player_name TEXT NOT NULL,
    avatar TEXT,
    score INTEGER DEFAULT 0,
    wins INTEGER DEFAULT 0,
    losses INTEGER DEFAULT 0,
    games INTEGER DEFAULT 0,
    win_rate REAL DEFAULT 0.0,
    rating INTEGER DEFAULT 1000,
    leaderboard_type INTEGER DEFAULT 4,  -- 0=日, 1=周, 2=月, 3=赛季, 4=全局
    last_update INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(player_id, leaderboard_type),
    FOREIGN KEY(player_id) REFERENCES players(player_id) ON DELETE CASCADE
);

-- 创建索引以加快查询
CREATE INDEX IF NOT EXISTS idx_leaderboard_type ON leaderboard(leaderboard_type);
CREATE INDEX IF NOT EXISTS idx_leaderboard_rating ON leaderboard(rating DESC);
CREATE INDEX IF NOT EXISTS idx_leaderboard_player_type ON leaderboard(player_id, leaderboard_type);
CREATE INDEX IF NOT EXISTS idx_leaderboard_last_update ON leaderboard(last_update);

-- 创建排行榜历史记录表 (用于追踪排名变化)
CREATE TABLE IF NOT EXISTS leaderboard_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    player_id TEXT NOT NULL,
    leaderboard_type INTEGER,
    rank INTEGER,
    rating INTEGER,
    wins INTEGER,
    losses INTEGER,
    score INTEGER,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY(player_id) REFERENCES players(player_id) ON DELETE CASCADE
);

-- 创建索引
CREATE INDEX IF NOT EXISTS idx_leaderboard_history_player ON leaderboard_history(player_id);
CREATE INDEX IF NOT EXISTS idx_leaderboard_history_type ON leaderboard_history(leaderboard_type);
CREATE INDEX IF NOT EXISTS idx_leaderboard_history_time ON leaderboard_history(recorded_at);

-- 创建排行榜每日重置记录表
CREATE TABLE IF NOT EXISTS leaderboard_resets (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    leaderboard_type INTEGER NOT NULL,
    reset_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    players_affected INTEGER DEFAULT 0
);

-- 创建索引
CREATE INDEX IF NOT EXISTS idx_leaderboard_resets_type ON leaderboard_resets(leaderboard_type);
CREATE INDEX IF NOT EXISTS idx_leaderboard_resets_time ON leaderboard_resets(reset_time);
