package queue

import (
	"context"
	"fmt"
	"strconv"
	"sync"
	"time"

	"github.com/redis/go-redis/v9"
)

// 分配与座位种类常量（ADR ParticipantKind 稳定值）。
const (
	StatusAssigned = "assigned"
	// StatusFailed Worker 失联等房间级失败终态（#256；ADR ROOM_FAILED）。
	StatusFailed = "failed"
	// StatusCompleted 正常终局完成（#256 容量释放）。
	StatusCompleted = "completed"
	// FailCodeRoomFailed 稳定失败码；HTTP 查询原样暴露。
	FailCodeRoomFailed = "ROOM_FAILED"

	SeatKindHuman = "HUMAN"
	SeatKindAI    = "AI"

	defaultScanInterval = 200 * time.Millisecond
	roomTTL             = 24 * time.Hour
	// maxRoomsPerPoolPerScan 单次 MatchAll 对每个池的开房上限，防止异常死循环。
	maxRoomsPerPoolPerScan = 64
	// maxMatchCommitRetries 候选变化时重试次数。
	maxMatchCommitRetries = 8
	// poolScanWindow 每次 ZRANGE 窗口大小。
	poolScanWindow = 31 // inclusive end index → 32 members
	// maxStaleCleanRounds 单次 peek/commit 清理 stale 的有界轮数；耗尽则本次不匹配。
	maxStaleCleanRounds = 64
	// matcherSafeErrorDetail 后台 OnError 固定安全文案（永不含原始 err / secret / token）。
	matcherSafeErrorDetail = "operation failed"
)

// RoomTokenIssuer 签发房间令牌（由 tokens.Service 实现）。
// roundKind / gameMode / participants 为 #240 不可篡改房间启动声明。
type RoomTokenIssuer interface {
	IssueRoomToken(sessionID, roomID string, seat int, roundKind, gameMode string, participants []string) (token string, expiresAt time.Time, err error)
}

// WorkerRegistry 为 #256 匹配所需的 Redis Worker 键空间（真实注册表）。
type WorkerRegistry interface {
	IndexKey() string
	KeyPrefix() string
	RoomsKey(workerID string) string
}

// MatchParams 单次池匹配参数。
// 游戏/语音地址由 Redis 原子选择的已注册 Worker 决定，不再接受静态端点覆盖。
type MatchParams struct {
	TokenIssuer RoomTokenIssuer
}

// MatchResult 单次池匹配结果。
type MatchResult struct {
	Matched    bool
	RoomID     string
	HumanCount int
	AICount    int
	TicketIDs  []string
}

// SeatOccupant 房间座位占用。
type SeatOccupant struct {
	Kind     string
	TicketID string
	GuestID  string
}

// Room 持久化在 Redis 的临时房间状态。
type Room struct {
	RoomID      string
	Worker      string
	VoiceWorker string
	WorkerID    string
	Status      string // active | failed
	FailCode    string
	RoundKind   RoundKind
	GameMode    GameMode
	HumanCount  int
	AICount     int
	CreatedAt   int64 // Unix 毫秒
	Seats       map[int]SeatOccupant
}

type matchCandidate struct {
	TicketID string
	GuestID  string
	ScoreMs  int64
}

// MatchPool 对指定规则池尝试一次匹配（真实 Redis 原子完整提交）。
// 流程：只读 peek 候选 → 预签发全部 room_token → 单次 Lua 在同一原子提交中
// 选择租约有效且有余量的 Worker、预留容量、写 room + 全部 ticket。
// 提交前对外不可见 assigned；无可用 Worker 时不消费队列。
func (s *Service) MatchPool(ctx context.Context, rk RoundKind, gm GameMode, params MatchParams) (MatchResult, error) {
	if err := ValidateRules(rk, gm); err != nil {
		return MatchResult{}, err
	}
	if params.TokenIssuer == nil {
		return MatchResult{}, fmt.Errorf("token issuer required")
	}
	if s.workers == nil {
		return MatchResult{}, fmt.Errorf("worker registry required")
	}
	// STANDARD 硬隔离：脚本内写入空 voice；TRASH_TALK 使用注册 Worker 的 voice_endpoint。
	wantVoice := 0
	if gm == GameModeTrashTalk {
		wantVoice = 1
	}

	for attempt := 0; attempt < maxMatchCommitRetries; attempt++ {
		cands, ready, err := s.peekMatchCandidates(ctx, rk, gm)
		if err != nil {
			return MatchResult{}, err
		}
		if !ready || len(cands) == 0 {
			return MatchResult{}, nil
		}

		roomID, err := s.idGen.NewID()
		if err != nil {
			return MatchResult{}, err
		}

		// 预签发：失败则不写 Redis，池与 ticket 保持 waiting。
		participants := make([]string, 4)
		for i := 0; i < 4; i++ {
			if i < len(cands) {
				participants[i] = SeatKindHuman
			} else {
				participants[i] = SeatKindAI
			}
		}
		tokens := make([]string, len(cands))
		for i, c := range cands {
			tok, _, err := params.TokenIssuer.IssueRoomToken(
				c.GuestID, roomID, i, string(rk), string(gm), participants,
			)
			if err != nil {
				return MatchResult{}, fmt.Errorf("issue room token: %w", err)
			}
			tokens[i] = tok
		}

		nowMs := s.clock.Now().UTC().UnixMilli()
		// ARGV：now, wait, room, ttl, ticket_prefix, guest_prefix, rk, gm, human_count,
		//       workers_index, worker_key_prefix, want_voice, then humans...
		args := make([]interface{}, 0, 12+len(cands)*4)
		args = append(args,
			nowMs,
			QueueWaitDeadline.Milliseconds(),
			roomID,
			int(roomTTL.Seconds()),
			s.prefix+"ticket:",
			s.prefix+"guest:",
			string(rk),
			string(gm),
			len(cands),
			s.workers.IndexKey(),
			s.workers.KeyPrefix(),
			wantVoice,
		)
		for i, c := range cands {
			args = append(args, c.TicketID, c.GuestID, i, tokens[i])
		}

		res, err := matchCommitScript.Run(ctx, s.rdb, []string{
			s.poolKey(rk, gm),
			s.roomKey(roomID),
		}, args...).Result()
		if err != nil {
			return MatchResult{}, err
		}
		arr, ok := res.([]interface{})
		if !ok || len(arr) < 1 {
			return MatchResult{}, fmt.Errorf("unexpected match script result: %v", res)
		}
		kind, _ := arr[0].(string)
		switch kind {
		case "NONE", "WAIT", "NO_CAPACITY":
			// NO_CAPACITY：有 waiting 候选但无健康有余量 Worker；不消费队列，本次不匹配。
			return MatchResult{}, nil
		case "RETRY":
			continue
		case "ASSIGNED":
			humanCount, err := atoiIface(arr[1])
			if err != nil {
				return MatchResult{}, err
			}
			ticketIDs := make([]string, 0, humanCount)
			for i := 0; i < humanCount; i++ {
				ticketIDs = append(ticketIDs, cands[i].TicketID)
			}
			return MatchResult{
				Matched:    true,
				RoomID:     roomID,
				HumanCount: humanCount,
				AICount:    4 - humanCount,
				TicketIDs:  ticketIDs,
			}, nil
		default:
			return MatchResult{}, fmt.Errorf("unexpected match kind: %v", arr[0])
		}
	}
	return MatchResult{}, nil
}

// peekMatchCandidates 选取当前可开房的最早 1–4 个有效 waiting ticket。
// 若窗口内存在 stale（缺失/非 waiting），批量 ZREM 后从头重读；仅当窗口无 stale
// 时才据 valid 数决定 4 真人或 deadline AI 补位。清理有界；耗尽则本次不匹配。
// 清理只动 ZSet stale member，不改任何 waiting ticket 字段。
func (s *Service) peekMatchCandidates(ctx context.Context, rk RoundKind, gm GameMode) ([]matchCandidate, bool, error) {
	pkey := s.poolKey(rk, gm)
	for round := 0; round < maxStaleCleanRounds; round++ {
		members, err := s.rdb.ZRangeWithScores(ctx, pkey, 0, int64(poolScanWindow)).Result()
		if err != nil {
			return nil, false, err
		}
		if len(members) == 0 {
			return nil, false, nil
		}

		cands := make([]matchCandidate, 0, 4)
		stale := make([]interface{}, 0)
		windowClean := true
		for _, m := range members {
			tid, ok := m.Member.(string)
			if !ok || tid == "" {
				windowClean = false
				continue
			}
			tk, err := s.loadTicket(ctx, tid)
			if err != nil || tk.Status != StatusWaiting {
				stale = append(stale, tid)
				windowClean = false
				continue
			}
			scoreMs := scoreToUnixMilli(int64(m.Score))
			if qms := tk.QueuedAt.Time().UnixMilli(); qms > 0 {
				scoreMs = qms
			}
			if len(cands) < 4 {
				cands = append(cands, matchCandidate{
					TicketID: tid,
					GuestID:  tk.GuestID,
					ScoreMs:  scoreMs,
				})
			}
		}

		if len(stale) > 0 {
			// 仅移除明确非 waiting / missing 的 member；多实例 ZREM 幂等安全。
			if err := s.rdb.ZRem(ctx, pkey, stale...).Err(); err != nil {
				return nil, false, err
			}
			// 清 stale 后必须从头重读，禁止用未完整扫描的 1–3 人直接 AI 补位。
			continue
		}
		if !windowClean {
			// 无 stale 列表但窗口异常：不匹配
			return nil, false, nil
		}

		// 窗口内无 stale，可安全根据 valid 数决策
		if len(cands) == 0 {
			return nil, false, nil
		}
		if len(cands) < 4 {
			nowMs := s.clock.Now().UTC().UnixMilli()
			if nowMs < cands[0].ScoreMs+QueueWaitDeadline.Milliseconds() {
				return nil, false, nil
			}
		}
		return cands, true, nil
	}
	// 清理轮次耗尽：宁可本次不匹配，也不能错误 AI 补位。
	return nil, false, nil
}

func scoreToUnixMilli(score int64) int64 {
	if score > 0 && score < 1_000_000_000_000 {
		return score * 1000
	}
	return score
}

// GetRoom 读取 Redis 中的房间临时状态（跨 CP 实例可见）。
func (s *Service) GetRoom(ctx context.Context, roomID string) (Room, error) {
	if roomID == "" {
		return Room{}, ErrNotFound
	}
	m, err := s.rdb.HGetAll(ctx, s.roomKey(roomID)).Result()
	if err != nil {
		return Room{}, err
	}
	if len(m) == 0 {
		return Room{}, ErrNotFound
	}
	humanCount, _ := strconv.Atoi(m["human_count"])
	aiCount, _ := strconv.Atoi(m["ai_count"])
	createdAt, _ := strconv.ParseInt(m["created_at"], 10, 64)
	room := Room{
		RoomID:      m["room_id"],
		Worker:      m["worker"],
		VoiceWorker: m["voice_worker"],
		WorkerID:    m["worker_id"],
		Status:      m["status"],
		FailCode:    m["fail_code"],
		RoundKind:   RoundKind(m["round_kind"]),
		GameMode:    GameMode(m["game_mode"]),
		HumanCount:  humanCount,
		AICount:     aiCount,
		CreatedAt:   createdAt,
		Seats:       make(map[int]SeatOccupant, 4),
	}
	for seat := 0; seat < 4; seat++ {
		kind := m[fmt.Sprintf("seat_%d_kind", seat)]
		if kind == "" {
			continue
		}
		room.Seats[seat] = SeatOccupant{
			Kind:     kind,
			TicketID: m[fmt.Sprintf("seat_%d_ticket_id", seat)],
			GuestID:  m[fmt.Sprintf("seat_%d_guest_id", seat)],
		}
	}
	return room, nil
}

func (s *Service) roomKey(roomID string) string {
	return s.prefix + "room:" + roomID
}

// matchCommitScript 原子提交完整分配（#256）：
// - 有界循环：ZRANGE 窗口内 stale 先 ZREM 再重扫；仅窗口干净时决策
// - 重验期望集合仍为当前最早有效 waiting
// - 在同一脚本内选择租约有效且 capacity > max(reserved, reported) 的 Worker 并 HINCRBY reserved
// - 一次写入 room + 全部 ticket 完整字段（含 room_token / worker_id）
// ARGV：now, wait, room_id, ttl, ticket_prefix, guest_prefix, rk, gm, human_count,
//
//	workers_index, worker_key_prefix, want_voice, then (tid,guest,seat,token)*
var matchCommitScript = redis.NewScript(`
local pkey = KEYS[1]
local rkey = KEYS[2]
local now_ms = tonumber(ARGV[1])
local wait_ms = tonumber(ARGV[2])
local room_id = ARGV[3]
local ttl = tonumber(ARGV[4])
local ticket_prefix = ARGV[5]
local guest_prefix = ARGV[6]
local round_kind = ARGV[7]
local game_mode = ARGV[8]
local human_count = tonumber(ARGV[9])
local workers_index = ARGV[10]
local worker_prefix = ARGV[11]
local want_voice = tonumber(ARGV[12])
local max_clean = 64

if human_count < 1 or human_count > 4 then
  return {'RETRY'}
end

local expect = {}
for i = 0, human_count - 1 do
  local base = 13 + i * 4
  expect[i + 1] = {
    tid = ARGV[base],
    guest = ARGV[base + 1],
    seat = ARGV[base + 2],
    token = ARGV[base + 3]
  }
end

local valid_ids = {}
local valid_scores = {}
local cleaned = false
for round = 1, max_clean do
  local members = redis.call('ZRANGE', pkey, 0, 31, 'WITHSCORES')
  valid_ids = {}
  valid_scores = {}
  local stale = {}
  for i = 1, #members, 2 do
    local tid = members[i]
    local score = tonumber(members[i + 1])
    local tkey = ticket_prefix .. tid
    local st = redis.call('HGET', tkey, 'status')
    if st == 'waiting' then
      if score > 0 and score < 1000000000000 then
        score = score * 1000
      end
      table.insert(valid_ids, tid)
      table.insert(valid_scores, score)
    else
      table.insert(stale, tid)
    end
  end
  if #stale > 0 then
    for _, tid in ipairs(stale) do
      redis.call('ZREM', pkey, tid)
    end
    cleaned = true
  else
    cleaned = false
    break
  end
end
if cleaned then
  return {'RETRY'}
end

if #valid_ids == 0 then
  return {'NONE'}
end

local take = #valid_ids
if take > 4 then
  take = 4
end
if take ~= human_count then
  return {'RETRY'}
end

for i = 1, take do
  if valid_ids[i] ~= expect[i].tid then
    return {'RETRY'}
  end
  local tkey = ticket_prefix .. expect[i].tid
  local st = redis.call('HGET', tkey, 'status')
  local guest = redis.call('HGET', tkey, 'guest_id')
  if st ~= 'waiting' or guest ~= expect[i].guest then
    return {'RETRY'}
  end
end

if take < 4 then
  local earliest = valid_scores[1]
  if now_ms < (earliest + wait_ms) then
    return {'WAIT'}
  end
end

-- 原子选择健康有余量 Worker：used = max(reserved, reported)；prefer lower used, then worker_id
local best_id = nil
local best_used = nil
local best_game = nil
local best_voice = nil
local wmembers = redis.call('SMEMBERS', workers_index)
for _, wid in ipairs(wmembers) do
  local wkey = worker_prefix .. 'worker:' .. wid
  local lease = tonumber(redis.call('HGET', wkey, 'lease_expires_at_ms') or '0')
  if lease > now_ms then
    local cap = tonumber(redis.call('HGET', wkey, 'capacity') or '0')
    local reserved = tonumber(redis.call('HGET', wkey, 'reserved_rooms') or '0')
    local reported = tonumber(redis.call('HGET', wkey, 'reported_rooms') or '0')
    local used = reserved
    if reported > used then used = reported end
    if used < cap then
      local game = redis.call('HGET', wkey, 'game_endpoint') or ''
      local voice = redis.call('HGET', wkey, 'voice_endpoint') or ''
      if game ~= '' then
        if want_voice == 1 and voice == '' then
          -- TRASH_TALK 需要语音端点
        else
          if best_id == nil or used < best_used or (used == best_used and wid < best_id) then
            best_id = wid
            best_used = used
            best_game = game
            best_voice = voice
          end
        end
      end
    end
  end
end

if best_id == nil then
  return {'NO_CAPACITY'}
end

local worker = best_game
local voice_worker = ''
if want_voice == 1 then
  voice_worker = best_voice
end

local wkey = worker_prefix .. 'worker:' .. best_id
redis.call('HINCRBY', wkey, 'reserved_rooms', 1)
redis.call('SADD', worker_prefix .. 'worker_rooms:' .. best_id, room_id)

redis.call('HSET', rkey,
  'room_id', room_id,
  'worker', worker,
  'worker_id', best_id,
  'status', 'active',
  'round_kind', round_kind,
  'game_mode', game_mode,
  'human_count', tostring(human_count),
  'ai_count', tostring(4 - human_count),
  'created_at', tostring(now_ms))
if voice_worker ~= nil and voice_worker ~= '' then
  redis.call('HSET', rkey, 'voice_worker', voice_worker)
else
  redis.call('HDEL', rkey, 'voice_worker')
end

for seat = 0, 3 do
  if seat < human_count then
    local e = expect[seat + 1]
    local tkey = ticket_prefix .. e.tid
    redis.call('HSET', tkey,
      'status', 'assigned',
      'room_id', room_id,
      'seat', tostring(seat),
      'worker', worker,
      'room_token', e.token)
    if voice_worker ~= nil and voice_worker ~= '' then
      redis.call('HSET', tkey, 'voice_worker', voice_worker)
    else
      redis.call('HDEL', tkey, 'voice_worker')
    end
    redis.call('EXPIRE', tkey, ttl)
    redis.call('ZREM', pkey, e.tid)
    local gkey = guest_prefix .. e.guest .. ':' .. round_kind .. ':' .. game_mode
    local cur = redis.call('GET', gkey)
    if cur == e.tid then
      redis.call('DEL', gkey)
    end
    redis.call('HSET', rkey,
      'seat_' .. seat .. '_kind', 'HUMAN',
      'seat_' .. seat .. '_ticket_id', e.tid,
      'seat_' .. seat .. '_guest_id', e.guest)
  else
    redis.call('HSET', rkey, 'seat_' .. seat .. '_kind', 'AI')
  end
end
redis.call('EXPIRE', rkey, ttl)
return {'ASSIGNED', tostring(human_count), best_id, worker}
`)

func atoiIface(v interface{}) (int, error) {
	switch x := v.(type) {
	case int:
		return x, nil
	case int64:
		return int(x), nil
	case string:
		return strconv.Atoi(x)
	default:
		return 0, fmt.Errorf("not an int: %T", v)
	}
}

// MatcherErrorFunc 后台安全错误回调。
// 仅暴露稳定操作类别 op 与固定安全文案 safeDetail；绝不传入原始 err.Error()。
type MatcherErrorFunc func(op string, safeDetail string)

// MatcherOptions 构造后台匹配器。
type MatcherOptions struct {
	Service      *Service
	TokenIssuer  RoomTokenIssuer
	ScanInterval time.Duration
	// OnError 可选：后台 loop 中 MatchAll 失败时调用（载荷已去敏）。
	OnError MatcherErrorFunc
}

// Matcher 在 Control Plane 运行期间自动推进匹配；可优雅启停。
// Worker 地址来自 Redis 注册表原子选择，不使用静态 WORKER_ENDPOINT。
type Matcher struct {
	svc      *Service
	issuer   RoomTokenIssuer
	interval time.Duration
	onError  MatcherErrorFunc

	startOnce sync.Once
	stopOnce  sync.Once
	stopCh    chan struct{}
	doneCh    chan struct{}
}

// NewMatcher 创建匹配器；Service 必须已注入 WorkerRegistry。
func NewMatcher(opts MatcherOptions) (*Matcher, error) {
	if opts.Service == nil {
		return nil, fmt.Errorf("queue service required")
	}
	if opts.TokenIssuer == nil {
		return nil, fmt.Errorf("token issuer required")
	}
	if opts.Service.workers == nil {
		return nil, fmt.Errorf("worker registry required")
	}
	interval := opts.ScanInterval
	if interval <= 0 {
		interval = defaultScanInterval
	}
	return &Matcher{
		svc:      opts.Service,
		issuer:   opts.TokenIssuer,
		interval: interval,
		onError:  opts.OnError,
		stopCh:   make(chan struct{}),
		doneCh:   make(chan struct{}),
	}, nil
}

// Start 启动后台扫描；重复调用安全。
func (m *Matcher) Start() {
	m.startOnce.Do(func() {
		go m.loop()
	})
}

// Stop 停止后台扫描并等待退出；可重复调用。
// 若从未 Start，则直接标记完成，避免等待泄漏。
func (m *Matcher) Stop(ctx context.Context) error {
	m.startOnce.Do(func() {
		close(m.doneCh)
	})
	m.stopOnce.Do(func() {
		close(m.stopCh)
	})
	select {
	case <-m.doneCh:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

// MatchAll 扫描全部四个规则池；每池持续消费直到无可立即匹配（有界）。
func (m *Matcher) MatchAll(ctx context.Context) error {
	combos := []struct {
		rk RoundKind
		gm GameMode
	}{
		{RoundKindEast, GameModeStandard},
		{RoundKindEast, GameModeTrashTalk},
		{RoundKindHanchan, GameModeStandard},
		{RoundKindHanchan, GameModeTrashTalk},
	}
	params := MatchParams{
		TokenIssuer: m.issuer,
	}
	for _, c := range combos {
		for i := 0; i < maxRoomsPerPoolPerScan; i++ {
			res, err := m.svc.MatchPool(ctx, c.rk, c.gm, params)
			if err != nil {
				return err
			}
			if !res.Matched {
				break
			}
		}
	}
	return nil
}

func (m *Matcher) reportError(op string, err error) {
	if err == nil || m.onError == nil {
		return
	}
	// 后台日志入口：永不转发原始错误正文（可能含 secret/token）。
	_ = err
	m.onError(op, matcherSafeErrorDetail)
}

func (m *Matcher) loop() {
	defer close(m.doneCh)
	ticker := time.NewTicker(m.interval)
	defer ticker.Stop()
	if err := m.MatchAll(context.Background()); err != nil {
		m.reportError("match_all", err)
	}
	for {
		select {
		case <-m.stopCh:
			return
		case <-ticker.C:
			if err := m.MatchAll(context.Background()); err != nil {
				m.reportError("match_all", err)
			}
		}
	}
}
