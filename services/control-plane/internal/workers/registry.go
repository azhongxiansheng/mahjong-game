// Package workers 提供 Headless Worker 注册、租约、容量与失联回收（#256）。
// Control Plane 统一写 Redis；Worker 不直连 Redis。网络端到端未验证。
package workers

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"
)

const (
	defaultKeyPrefix = "cp:v1:"
	// DefaultLeaseTTL 安全默认租约时长（非密钥）。
	DefaultLeaseTTL = 15 * time.Second
	// DefaultReapInterval 安全默认回收扫描间隔。
	DefaultReapInterval = 1 * time.Second
	// FailCodeRoomFailed ADR 冻结的房间级失败码。
	FailCodeRoomFailed = "ROOM_FAILED"
	// StatusFailed ticket/room 失联失败终态。
	StatusFailed = "failed"
	// StatusActive 未结束房间状态。
	StatusActive = "active"
	// StatusCompleted 正常终局完成（释放容量；不再被失联标 failed）。
	StatusCompleted = "completed"
	// StatusAssigned ticket 已分配（与 queue 包对齐字面量）。
	StatusAssigned = "assigned"

	// Complete 结果码（稳定，不含 secret）。
	CompleteOK            = "OK"
	CompleteIdempotent    = "OK_IDEM"
	CompleteNotFound      = "NOT_FOUND"
	CompleteWrongWorker   = "WRONG_WORKER"
	CompleteAlreadyFailed = "ALREADY_FAILED"
	CompleteBadState      = "BAD_STATE"

	// Fail 结果码（#376 READY 超时等；幂等，不含 secret）。
	FailOK          = "OK"
	FailIdempotent  = "OK_IDEM"
	FailNotFound    = "NOT_FOUND"
	FailWrongWorker = "WRONG_WORKER"
	FailAlreadyDone = "ALREADY_COMPLETED"
	FailBadState    = "BAD_STATE"

	workerHashTTL = 24 * time.Hour
)

// Clock 可注入 wall clock（Unix 时间语义）。
type Clock interface {
	Now() time.Time
}

type realClock struct{}

func (realClock) Now() time.Time { return time.Now().UTC() }

// Registration Worker → CP 注册/续租请求体。
type Registration struct {
	WorkerID      string
	GameEndpoint  string
	VoiceEndpoint string
	Capacity      int
	// ActiveRooms 为 Worker 报告的实际未结束房间数；只可使占用更保守。
	ActiveRooms int
}

// Record Redis 中的 Worker 视图。
type Record struct {
	WorkerID         string
	GameEndpoint     string
	VoiceEndpoint    string
	Capacity         int
	ReportedRooms    int
	ReservedRooms    int
	LeaseExpiresAtMs int64
	UpdatedAtMs      int64
}

// LeaseResult 注册/续租成功结果。
type LeaseResult struct {
	WorkerID         string
	LeaseExpiresAtMs int64
	LeaseTTL         time.Duration
}

// Options 构造注册表。
type Options struct {
	Redis     *redis.Client
	KeyPrefix string
	Clock     Clock
	// LeaseTTL 租约时长；<=0 用 DefaultLeaseTTL。
	LeaseTTL time.Duration
	// CasualPrefix 与 queue.Service 房间/ticket 键前缀对齐（默认 cp:v1:casual:）。
	CasualPrefix string
}

// Registry Redis 权威 Worker 注册表。
type Registry struct {
	rdb          *redis.Client
	prefix       string
	casualPrefix string
	clock        Clock
	leaseTTL     time.Duration
}

// NewRegistry 创建注册表；Redis 必填。
func NewRegistry(opts Options) (*Registry, error) {
	if opts.Redis == nil {
		return nil, fmt.Errorf("redis client required")
	}
	prefix := opts.KeyPrefix
	if prefix == "" {
		prefix = defaultKeyPrefix
	}
	casual := opts.CasualPrefix
	if casual == "" {
		casual = defaultKeyPrefix + "casual:"
	}
	ttl := opts.LeaseTTL
	if ttl <= 0 {
		ttl = DefaultLeaseTTL
	}
	clk := opts.Clock
	if clk == nil {
		clk = realClock{}
	}
	return &Registry{
		rdb:          opts.Redis,
		prefix:       prefix,
		casualPrefix: casual,
		clock:        clk,
		leaseTTL:     ttl,
	}, nil
}

// LeaseTTL 返回当前租约时长。
func (r *Registry) LeaseTTL() time.Duration { return r.leaseTTL }

// IndexKey 返回 workers 索引 SET 键。
func (r *Registry) IndexKey() string { return r.prefix + "workers" }

// WorkerKey 返回 worker hash 键。
func (r *Registry) WorkerKey(workerID string) string {
	return r.prefix + "worker:" + workerID
}

// RoomsKey 返回 worker 关联未结束房间 SET 键。
func (r *Registry) RoomsKey(workerID string) string {
	return r.prefix + "worker_rooms:" + workerID
}

// CasualPrefix 返回 casual 队列键前缀（供 Matcher Lua）。
func (r *Registry) CasualPrefix() string { return r.casualPrefix }

// KeyPrefix 返回 registry 前缀。
func (r *Registry) KeyPrefix() string { return r.prefix }

// Register 注册或续租同一 worker_id；刷新租约与端点，不复活已失败房间。
// reserved_rooms 不被 reported 降低。
func (r *Registry) Register(ctx context.Context, reg Registration) (LeaseResult, error) {
	reg.WorkerID = strings.TrimSpace(reg.WorkerID)
	reg.GameEndpoint = strings.TrimSpace(reg.GameEndpoint)
	reg.VoiceEndpoint = strings.TrimSpace(reg.VoiceEndpoint)
	if reg.WorkerID == "" {
		return LeaseResult{}, fmt.Errorf("worker_id required")
	}
	if reg.GameEndpoint == "" {
		return LeaseResult{}, fmt.Errorf("game_endpoint required")
	}
	if reg.VoiceEndpoint == "" {
		return LeaseResult{}, fmt.Errorf("voice_endpoint required")
	}
	if reg.Capacity < 1 {
		return LeaseResult{}, fmt.Errorf("capacity must be >= 1")
	}
	if reg.ActiveRooms < 0 {
		return LeaseResult{}, fmt.Errorf("active_rooms must be >= 0")
	}

	nowMs := r.clock.Now().UTC().UnixMilli()
	leaseMs := r.leaseTTL.Milliseconds()
	expires := nowMs + leaseMs

	// ARGV: now, expires, ttl_sec, worker_id, game, voice, capacity, active_rooms
	res, err := registerScript.Run(ctx, r.rdb, []string{
		r.WorkerKey(reg.WorkerID),
		r.IndexKey(),
	}, nowMs, expires, int(workerHashTTL.Seconds()),
		reg.WorkerID, reg.GameEndpoint, reg.VoiceEndpoint,
		reg.Capacity, reg.ActiveRooms,
	).Result()
	if err != nil {
		return LeaseResult{}, err
	}
	arr, ok := res.([]interface{})
	if !ok || len(arr) < 2 {
		return LeaseResult{}, fmt.Errorf("unexpected register result: %v", res)
	}
	exp, err := ifaceToInt64(arr[1])
	if err != nil {
		return LeaseResult{}, err
	}
	return LeaseResult{
		WorkerID:         reg.WorkerID,
		LeaseExpiresAtMs: exp,
		LeaseTTL:         r.leaseTTL,
	}, nil
}

// Get 读取 Worker 记录；不存在返回 false。
func (r *Registry) Get(ctx context.Context, workerID string) (Record, bool, error) {
	workerID = strings.TrimSpace(workerID)
	if workerID == "" {
		return Record{}, false, nil
	}
	m, err := r.rdb.HGetAll(ctx, r.WorkerKey(workerID)).Result()
	if err != nil {
		return Record{}, false, err
	}
	if len(m) == 0 {
		return Record{}, false, nil
	}
	rec, err := recordFromMap(m)
	if err != nil {
		return Record{}, false, err
	}
	return rec, true, nil
}

// IsSelectable 租约有效且仍有余量（capacity > max(reserved, reported)）。
func (r *Registry) IsSelectable(ctx context.Context, workerID string) (bool, error) {
	rec, ok, err := r.Get(ctx, workerID)
	if err != nil || !ok {
		return false, err
	}
	nowMs := r.clock.Now().UTC().UnixMilli()
	if rec.LeaseExpiresAtMs <= nowMs {
		return false, nil
	}
	used := rec.ReservedRooms
	if rec.ReportedRooms > used {
		used = rec.ReportedRooms
	}
	return used < rec.Capacity, nil
}

// CompleteRoom 权威房间正常完成：仅 active 且归属该 worker 的房间可原子转 completed，
// 从 worker_rooms 移除并将 reserved 恰减 1（幂等；不复活 failed；不把 reserved 减成负数）。
func (r *Registry) CompleteRoom(ctx context.Context, workerID, roomID string) (string, error) {
	workerID = strings.TrimSpace(workerID)
	roomID = strings.TrimSpace(roomID)
	if workerID == "" || roomID == "" {
		return CompleteBadState, fmt.Errorf("worker_id and room_id required")
	}
	res, err := completeRoomScript.Run(ctx, r.rdb, []string{
		r.WorkerKey(workerID),
		r.RoomsKey(workerID),
		r.casualPrefix + "room:" + roomID,
	}, workerID, roomID, StatusCompleted, StatusActive, StatusFailed).Result()
	if err != nil {
		return "", err
	}
	kind, _ := res.(string)
	if kind == "" {
		if arr, ok := res.([]interface{}); ok && len(arr) > 0 {
			kind, _ = arr[0].(string)
		}
	}
	switch kind {
	case CompleteOK, CompleteIdempotent, CompleteNotFound, CompleteWrongWorker, CompleteAlreadyFailed, CompleteBadState:
		return kind, nil
	default:
		return kind, fmt.Errorf("unexpected complete result: %v", res)
	}
}

// FailRoom 权威房间失败（#376 READY 超时等）：active 且归属该 worker → failed + ROOM_FAILED，
// assigned tickets 同步 failed；释放 reserved 恰 1（幂等；不复活 completed）。
// failCode 仅接受空（归一 ROOM_FAILED）或 ROOM_FAILED；其它值拒绝。
func (r *Registry) FailRoom(ctx context.Context, workerID, roomID, failCode string) (string, error) {
	workerID = strings.TrimSpace(workerID)
	roomID = strings.TrimSpace(roomID)
	failCode = strings.TrimSpace(failCode)
	if workerID == "" || roomID == "" {
		return FailBadState, fmt.Errorf("worker_id and room_id required")
	}
	if failCode == "" {
		failCode = FailCodeRoomFailed
	}
	if failCode != FailCodeRoomFailed {
		return FailBadState, fmt.Errorf("fail_code must be ROOM_FAILED")
	}
	res, err := failRoomScript.Run(ctx, r.rdb, []string{
		r.WorkerKey(workerID),
		r.RoomsKey(workerID),
		r.casualPrefix + "room:" + roomID,
		r.casualPrefix,
	}, workerID, roomID, StatusFailed, StatusActive, StatusCompleted, failCode).Result()
	if err != nil {
		return "", err
	}
	kind, _ := res.(string)
	if kind == "" {
		if arr, ok := res.([]interface{}); ok && len(arr) > 0 {
			kind, _ = arr[0].(string)
		}
	}
	switch kind {
	case FailOK, FailIdempotent, FailNotFound, FailWrongWorker, FailAlreadyDone, FailBadState:
		return kind, nil
	default:
		return kind, fmt.Errorf("unexpected fail result: %v", res)
	}
}

// ReapExpired 扫描失联 Worker：仅未结束 active 房间 → failed/ROOM_FAILED；
// completed 不改；完成后从选择索引 SREM（同 ID 恢复 Register 会再 SADD）。
func (r *Registry) ReapExpired(ctx context.Context) (int, error) {
	nowMs := r.clock.Now().UTC().UnixMilli()
	res, err := reapScript.Run(ctx, r.rdb, []string{
		r.IndexKey(),
		r.prefix,
		r.casualPrefix,
	}, nowMs, FailCodeRoomFailed).Result()
	if err != nil {
		return 0, err
	}
	n, err := ifaceToInt64(res)
	if err != nil {
		return 0, err
	}
	return int(n), nil
}

// IndexMembers 返回当前选择索引中的 worker_id（测试/诊断）。
func (r *Registry) IndexMembers(ctx context.Context) ([]string, error) {
	return r.rdb.SMembers(ctx, r.IndexKey()).Result()
}

func recordFromMap(m map[string]string) (Record, error) {
	capN, _ := strconv.Atoi(m["capacity"])
	reported, _ := strconv.Atoi(m["reported_rooms"])
	reserved, _ := strconv.Atoi(m["reserved_rooms"])
	lease, _ := strconv.ParseInt(m["lease_expires_at_ms"], 10, 64)
	updated, _ := strconv.ParseInt(m["updated_at_ms"], 10, 64)
	return Record{
		WorkerID:         m["worker_id"],
		GameEndpoint:     m["game_endpoint"],
		VoiceEndpoint:    m["voice_endpoint"],
		Capacity:         capN,
		ReportedRooms:    reported,
		ReservedRooms:    reserved,
		LeaseExpiresAtMs: lease,
		UpdatedAtMs:      updated,
	}, nil
}

func ifaceToInt64(v interface{}) (int64, error) {
	switch x := v.(type) {
	case int64:
		return x, nil
	case int:
		return int64(x), nil
	case string:
		return strconv.ParseInt(x, 10, 64)
	default:
		return 0, fmt.Errorf("not int64: %T", v)
	}
}

// registerScript：写入/刷新 worker；不降低 reserved_rooms；不触碰失败房间。
var registerScript = redis.NewScript(`
local wkey = KEYS[1]
local idx = KEYS[2]
local now_ms = tonumber(ARGV[1])
local expires = tonumber(ARGV[2])
local ttl = tonumber(ARGV[3])
local worker_id = ARGV[4]
local game = ARGV[5]
local voice = ARGV[6]
local capacity = tonumber(ARGV[7])
local active_rooms = tonumber(ARGV[8])

local prev_reserved = redis.call('HGET', wkey, 'reserved_rooms')
local reserved = 0
if prev_reserved then
  reserved = tonumber(prev_reserved) or 0
end

redis.call('HSET', wkey,
  'worker_id', worker_id,
  'game_endpoint', game,
  'voice_endpoint', voice,
  'capacity', tostring(capacity),
  'reported_rooms', tostring(active_rooms),
  'reserved_rooms', tostring(reserved),
  'lease_expires_at_ms', tostring(expires),
  'updated_at_ms', tostring(now_ms))
redis.call('EXPIRE', wkey, ttl)
redis.call('SADD', idx, worker_id)
return {'OK', tostring(expires)}
`)

// completeRoomScript：正常完成释放容量。
// KEYS: worker_hash, worker_rooms_set, room_hash
// ARGV: worker_id, room_id, completed, active, failed
var completeRoomScript = redis.NewScript(`
local wkey = KEYS[1]
local rset = KEYS[2]
local rkey = KEYS[3]
local worker_id = ARGV[1]
local room_id = ARGV[2]
local st_completed = ARGV[3]
local st_active = ARGV[4]
local st_failed = ARGV[5]

if redis.call('EXISTS', rkey) == 0 then
  return 'NOT_FOUND'
end
local st = redis.call('HGET', rkey, 'status')
if st == st_completed then
  -- 幂等：确保不在 rooms 集合且不重复减 reserved
  redis.call('SREM', rset, room_id)
  return 'OK_IDEM'
end
if st == st_failed then
  return 'ALREADY_FAILED'
end
if st ~= false and st ~= nil and st ~= '' and st ~= st_active then
  return 'BAD_STATE'
end
local owner = redis.call('HGET', rkey, 'worker_id')
if owner ~= worker_id then
  return 'WRONG_WORKER'
end
redis.call('HSET', rkey, 'status', st_completed)
redis.call('HDEL', rkey, 'fail_code')
redis.call('SREM', rset, room_id)
local reserved = tonumber(redis.call('HGET', wkey, 'reserved_rooms') or '0')
if reserved == nil then reserved = 0 end
if reserved > 0 then
  redis.call('HINCRBY', wkey, 'reserved_rooms', -1)
end
return 'OK'
`)

// failRoomScript：Worker 主动失败房间并释放容量（#376）。
// 始终先校验 owner，再处理 failed/completed/active（防止他 worker 对 failed 幂等成功）。
// KEYS: worker_hash, worker_rooms_set, room_hash, casual_prefix
// ARGV: worker_id, room_id, failed, active, completed, fail_code
var failRoomScript = redis.NewScript(`
local wkey = KEYS[1]
local rset = KEYS[2]
local rkey = KEYS[3]
local casual_prefix = KEYS[4]
local worker_id = ARGV[1]
local room_id = ARGV[2]
local st_failed = ARGV[3]
local st_active = ARGV[4]
local st_completed = ARGV[5]
local fail_code = ARGV[6]

if redis.call('EXISTS', rkey) == 0 then
  return 'NOT_FOUND'
end
local owner = redis.call('HGET', rkey, 'worker_id')
if owner ~= worker_id then
  return 'WRONG_WORKER'
end
local st = redis.call('HGET', rkey, 'status')
if st == st_failed then
  redis.call('SREM', rset, room_id)
  return 'OK_IDEM'
end
if st == st_completed then
  return 'ALREADY_COMPLETED'
end
if st ~= false and st ~= nil and st ~= '' and st ~= st_active then
  return 'BAD_STATE'
end
redis.call('HSET', rkey, 'status', st_failed, 'fail_code', fail_code)
for seat = 0, 3 do
  local tid = redis.call('HGET', rkey, 'seat_' .. seat .. '_ticket_id')
  if tid and tid ~= '' then
    local tkey = casual_prefix .. 'ticket:' .. tid
    local tst = redis.call('HGET', tkey, 'status')
    if tst == 'assigned' then
      redis.call('HSET', tkey, 'status', 'failed', 'fail_code', fail_code)
    end
  end
end
redis.call('SREM', rset, room_id)
local reserved = tonumber(redis.call('HGET', wkey, 'reserved_rooms') or '0')
if reserved == nil then reserved = 0 end
if reserved > 0 then
  redis.call('HINCRBY', wkey, 'reserved_rooms', -1)
end
return 'OK'
`)

// reapScript：对租约过期 Worker 的未结束房间与 assigned ticket 原子失败。
// completed 房间跳过；回收后从选择索引 SREM。
// KEYS: index, registry_prefix, casual_prefix
// ARGV: now_ms, fail_code
// 返回失败房间数。
var reapScript = redis.NewScript(`
local idx = KEYS[1]
local reg_prefix = KEYS[2]
local casual_prefix = KEYS[3]
local now_ms = tonumber(ARGV[1])
local fail_code = ARGV[2]
local failed_rooms = 0

local members = redis.call('SMEMBERS', idx)
for _, wid in ipairs(members) do
  local wkey = reg_prefix .. 'worker:' .. wid
  local lease = tonumber(redis.call('HGET', wkey, 'lease_expires_at_ms') or '0')
  if lease <= now_ms then
    local rset = reg_prefix .. 'worker_rooms:' .. wid
    local rooms = redis.call('SMEMBERS', rset)
    for _, rid in ipairs(rooms) do
      local rkey = casual_prefix .. 'room:' .. rid
      local st = redis.call('HGET', rkey, 'status')
      -- 仅未结束 active（或缺失 status 的历史 active）→ failed；completed 不改
      if st == 'completed' then
        redis.call('SREM', rset, rid)
      elseif st == false or st == nil or st == '' or st == 'active' then
        redis.call('HSET', rkey, 'status', 'failed', 'fail_code', fail_code)
        local human_count = tonumber(redis.call('HGET', rkey, 'human_count') or '0')
        if human_count == nil then human_count = 0 end
        for seat = 0, 3 do
          local tid = redis.call('HGET', rkey, 'seat_' .. seat .. '_ticket_id')
          if tid and tid ~= '' then
            local tkey = casual_prefix .. 'ticket:' .. tid
            local tst = redis.call('HGET', tkey, 'status')
            if tst == 'assigned' then
              redis.call('HSET', tkey,
                'status', 'failed',
                'fail_code', fail_code)
            end
          end
        end
        failed_rooms = failed_rooms + 1
        redis.call('SREM', rset, rid)
      else
        redis.call('SREM', rset, rid)
      end
    end
    if redis.call('EXISTS', wkey) == 1 then
      redis.call('HSET', wkey, 'reserved_rooms', '0')
    end
    -- 从选择索引移除，避免无限重扫；恢复注册会 SADD
    redis.call('SREM', idx, wid)
  end
end
return failed_rooms
`)
