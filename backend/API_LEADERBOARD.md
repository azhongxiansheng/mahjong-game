# 🏆 排行榜 API 文档

**版本**: v1.0  
**状态**: ✅ 已实现  
**语言**: Go + Gin + SQLite

---

## 📋 API 端点总览

| 方法 | 端点 | 描述 |
|------|------|------|
| GET | `/api/leaderboard` | 获取排行榜数据 |
| GET | `/api/leaderboard/rank/:player_id` | 获取玩家排名 |
| POST | `/api/leaderboard/update` | 更新玩家统计 |
| GET | `/api/leaderboard/stats` | 获取排行榜统计 |
| GET | `/api/leaderboard/export` | 导出排行榜 (JSON) |

---

## 📡 API 详细说明

### 1. 获取排行榜数据

**端点**: `GET /api/leaderboard`

**请求参数**:
```
type: int (可选, 默认 4)
  0 = 日排行
  1 = 周排行
  2 = 月排行
  3 = 赛季排行
  4 = 全局排行

limit: int (可选, 默认 100, 最大 1000)
  返回的玩家数量
```

**请求示例**:
```bash
GET /api/leaderboard?type=4&limit=100
```

**响应示例** (200 OK):
```json
{
  "success": true,
  "type": "全局排行",
  "count": 100,
  "data": [
    {
      "rank": 1,
      "player_id": "player_001",
      "player_name": "AliceHacker",
      "avatar": "https://example.com/avatar/alice.jpg",
      "score": 15000,
      "wins": 45,
      "losses": 5,
      "games": 50,
      "win_rate": 0.9,
      "rating": 1850,
      "last_update": 1635619200000
    },
    {
      "rank": 2,
      "player_id": "player_002",
      "player_name": "BobMaster",
      "avatar": "https://example.com/avatar/bob.jpg",
      "score": 12000,
      "wins": 40,
      "losses": 10,
      "games": 50,
      "win_rate": 0.8,
      "rating": 1750,
      "last_update": 1635619100000
    }
  ]
}
```

---

### 2. 获取玩家排名

**端点**: `GET /api/leaderboard/rank/:player_id`

**请求参数**:
```
player_id: string (路径参数)
type: int (可选, 默认 4)
```

**请求示例**:
```bash
GET /api/leaderboard/rank/player_001?type=4
```

**响应示例** (200 OK):
```json
{
  "success": true,
  "player_id": "player_001",
  "rank": 1
}
```

**错误响应** (404 Not Found):
```json
{
  "success": false,
  "message": "Player not found"
}
```

---

### 3. 更新玩家统计

**端点**: `POST /api/leaderboard/update`

**请求体**:
```json
{
  "player_id": "player_001",
  "player_name": "AliceHacker",
  "avatar": "https://example.com/avatar/alice.jpg",
  "score": 200,
  "wins": 1,
  "losses": 0,
  "rating_change": 25,
  "leaderboard_type": 4
}
```

**请求示例**:
```bash
curl -X POST http://localhost:8080/api/leaderboard/update \
  -H "Content-Type: application/json" \
  -d '{
    "player_id": "player_001",
    "player_name": "AliceHacker",
    "avatar": "https://example.com/avatar/alice.jpg",
    "score": 200,
    "wins": 1,
    "losses": 0,
    "rating_change": 25,
    "leaderboard_type": 4
  }'
```

**响应示例** (200 OK - 新玩家):
```json
{
  "success": true,
  "message": "Player stats updated",
  "new_rating": 1025,
  "new_wins": 1,
  "new_losses": 0,
  "win_rate": 1.0
}
```

**响应示例** (200 OK - 更新玩家):
```json
{
  "success": true,
  "message": "Player stats updated",
  "new_rating": 1870,
  "new_wins": 46,
  "new_losses": 5,
  "win_rate": 0.902
}
```

**错误响应** (400 Bad Request):
```json
{
  "success": false,
  "message": "Missing required fields"
}
```

---

### 4. 获取排行榜统计

**端点**: `GET /api/leaderboard/stats`

**请求参数**:
```
type: int (可选, 默认 4)
```

**请求示例**:
```bash
GET /api/leaderboard/stats?type=4
```

**响应示例** (200 OK):
```json
{
  "success": true,
  "data": {
    "total_players": 250,
    "avg_rating": 1234.5,
    "max_rating": 2100,
    "min_rating": 800
  }
}
```

---

### 5. 导出排行榜

**端点**: `GET /api/leaderboard/export`

**请求参数**:
```
type: int (可选, 默认 4)
limit: int (可选, 默认 100, 最大 1000)
```

**请求示例**:
```bash
GET /api/leaderboard/export?type=4&limit=50
```

**响应**: JSON 文件下载

**文件名**: `leaderboard_4.json`

**内容格式**: 与获取排行榜相同

---

## 🔄 数据流示例

### 游戏结束 → 排行榜更新流程

```
1. 游戏管理器检测游戏结束
   ↓
2. 计算玩家等级分变化 (ELO 算法)
   rating_change = calculate_rating_change(...)
   ↓
3. 构建更新请求
   {
     "player_id": "player_001",
     "wins": 1,
     "score": 150,
     "rating_change": 25
   }
   ↓
4. 发送 POST /api/leaderboard/update
   ↓
5. 后端更新数据库
   ↓
6. 返回新的排行数据
   {
     "new_rating": 1150,
     "new_wins": 11,
     "win_rate": 0.85
   }
   ↓
7. 前端刷新排行榜显示
```

---

## 🛠️ 数据库表结构

### leaderboard 表

```
id              INT PRIMARY KEY
player_id       TEXT NOT NULL UNIQUE (per type)
player_name     TEXT NOT NULL
avatar          TEXT
score           INT DEFAULT 0
wins            INT DEFAULT 0
losses          INT DEFAULT 0
games           INT DEFAULT 0
win_rate        REAL DEFAULT 0.0
rating          INT DEFAULT 1000
leaderboard_type INT DEFAULT 4
last_update     INT
created_at      TIMESTAMP
updated_at      TIMESTAMP
```

### 索引

```
idx_leaderboard_type       - 排行榜类型查询
idx_leaderboard_rating     - 排名排序
idx_leaderboard_player_type - 玩家查询
idx_leaderboard_last_update - 时间查询
```

---

## 📊 排行榜类型说明

| 类型 | 值 | 描述 | 重置周期 |
|------|---|------|---------|
| 日排行 | 0 | 每天排行 | 每天 00:00 |
| 周排行 | 1 | 每周排行 | 每周一 00:00 |
| 月排行 | 2 | 每月排行 | 每月 1 日 00:00 |
| 赛季排行 | 3 | 赛季排行 | 赛季结束 |
| 全局排行 | 4 | 全局排行 | 不重置 |

---

## ✅ API 使用清单

### 基本获取操作

- [x] 获取全球排行榜前 100 名
- [x] 获取特定类型排行榜
- [x] 查询单个玩家排名
- [x] 获取排行榜统计信息

### 数据更新操作

- [x] 创建新玩家记录
- [x] 更新玩家统计
- [x] 自动计算胜率
- [x] 记录更新时间戳

### 数据导出操作

- [x] 导出排行榜为 JSON
- [x] 指定导出数量
- [x] 指定导出类型

### 错误处理

- [x] 无效参数检查
- [x] 数据库错误处理
- [x] 缺失字段验证
- [x] 玩家不存在处理

---

## 🔐 安全性考虑

### 输入验证

```
✅ 类型参数: 必须在 0-4 范围内
✅ 数量限制: limit 最大 1000
✅ 玩家 ID: 非空字符串
✅ 名称: 非空字符串
```

### SQL 注入防护

```
✅ 使用参数化查询
✅ 所有用户输入都进行转义
✅ 类型检查和验证
```

### 速率限制 (推荐)

```
✅ GET /api/leaderboard: 100 requests/min
✅ POST /api/leaderboard/update: 10 requests/sec
✅ GET /api/leaderboard/export: 5 requests/min
```

---

## 📈 性能优化

### 查询优化

- [x] 按等级分建立索引
- [x] 按排行榜类型建立索引
- [x] 复合索引用于常见查询

### 缓存策略 (推荐)

```
缓存类型            有效期
排行榜数据          5 分钟
玩家排名            1 分钟
统计信息            10 分钟
```

### 批量操作

```
✅ 支持单个玩家更新
📋 推荐: 实现批量更新端点
```

---

## 🧪 测试用例

### 测试用例 1: 基本排行榜查询

```bash
curl -X GET "http://localhost:8080/api/leaderboard?type=4&limit=10"
```

预期: 返回前 10 名玩家

### 测试用例 2: 更新玩家统计

```bash
curl -X POST http://localhost:8080/api/leaderboard/update \
  -H "Content-Type: application/json" \
  -d '{
    "player_id": "test_player_1",
    "player_name": "TestPlayer",
    "avatar": "http://example.com/avatar.jpg",
    "score": 100,
    "wins": 1,
    "losses": 0,
    "rating_change": 20,
    "leaderboard_type": 4
  }'
```

预期: 返回成功并包含新等级分

### 测试用例 3: 获取玩家排名

```bash
curl -X GET "http://localhost:8080/api/leaderboard/rank/test_player_1?type=4"
```

预期: 返回玩家的当前排名

---

## 📝 API 响应码汇总

| 状态码 | 含义 | 场景 |
|--------|------|------|
| 200 | OK | 请求成功 |
| 400 | Bad Request | 参数无效 |
| 404 | Not Found | 资源不存在 |
| 500 | Server Error | 数据库错误 |

---

**API 版本**: v1.0  
**最后更新**: 2025-10-29  
**维护者**: 后端团队
