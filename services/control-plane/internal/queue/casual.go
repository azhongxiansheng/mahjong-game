// Package queue 提供公共休闲匹配队列（Redis ticket / 匹配池 / 取消 / 30s AI 补位）。
// 网络端到端未验证。
package queue

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"time"

	"github.com/redis/go-redis/v9"
)

// ADR 稳定枚举值（大小写敏感）。
const (
	RoundKindEast    RoundKind = "EAST"
	RoundKindHanchan RoundKind = "HANCHAN"

	GameModeStandard  GameMode = "STANDARD"
	GameModeTrashTalk GameMode = "TRASH_TALK"

	StatusWaiting   = "waiting"
	StatusCancelled = "cancelled"
	// StatusAssigned 定义于 match.go（分配成功终态）。

	// QueueWaitDeadline 最早 ticket 自 queued_at 起的匹配等待契约。
	QueueWaitDeadline = 30 * time.Second

	defaultKeyPrefix = "cp:v1:casual:"
	ticketTTL        = 24 * time.Hour
)

// RoundKind 局制。
type RoundKind string

// GameMode 游戏模式。
type GameMode string

// ErrInvalidRules 非法 round_kind / game_mode。
var ErrInvalidRules = errors.New("invalid queue rules")

// ErrNotFound ticket 不存在或不对调用方可见。
var ErrNotFound = errors.New("ticket not found")

// ErrForbidden ticket 存在但不属于调用方。
var ErrForbidden = errors.New("ticket forbidden")

// Clock 可注入时钟。
type Clock interface {
	Now() time.Time
}

type realClock struct{}

func (realClock) Now() time.Time { return time.Now().UTC() }

// IDGen 可注入 ticket id 生成器。
type IDGen interface {
	NewID() (string, error)
}

type cryptoIDGen struct{}

func (cryptoIDGen) NewID() (string, error) {
	return newUUIDv4()
}

// TicketTime 便于 JSON；与 Redis/HTTP 同源（整秒 RFC3339，亚秒到毫秒）。
type TicketTime time.Time

func (t TicketTime) MarshalJSON() ([]byte, error) {
	return json.Marshal(formatTicketTime(time.Time(t).UTC()))
}

func (t *TicketTime) UnmarshalJSON(b []byte) error {
	var s string
	if err := json.Unmarshal(b, &s); err != nil {
		return err
	}
	parsed, err := parseTicketTime(s)
	if err != nil {
		return err
	}
	*t = TicketTime(parsed.UTC())
	return nil
}

func (t TicketTime) Time() time.Time { return time.Time(t).UTC() }

// Ticket 队列票据。
type Ticket struct {
	TicketID   string     `json:"ticket_id"`
	GuestID    string     `json:"guest_id"`
	RoundKind  RoundKind  `json:"round_kind"`
	GameMode   GameMode   `json:"game_mode"`
	Status     string     `json:"status"`
	QueuedAt   TicketTime `json:"queued_at"`
	DeadlineAt TicketTime `json:"deadline_at"`
	// 以下字段仅 status=assigned 时有意义（跨 CP 实例 Redis 可读）。
	RoomID    string `json:"room_id,omitempty"`
	Seat      int    `json:"seat,omitempty"`
	Worker    string `json:"worker,omitempty"`
	RoomToken string `json:"room_token,omitempty"`
	HasSeat   bool   `json:"-"` // 内部：区分 seat=0 与未分配
}

// Options 构造队列服务。
type Options struct {
	Redis     *redis.Client
	KeyPrefix string
	Clock     Clock
	IDGen     IDGen
}

// Service 真实 Redis 队列。
type Service struct {
	rdb    *redis.Client
	prefix string
	clock  Clock
	idGen  IDGen
}

// NewService 创建队列服务；Redis 客户端必填。
func NewService(opts Options) (*Service, error) {
	if opts.Redis == nil {
		return nil, fmt.Errorf("redis client required")
	}
	prefix := opts.KeyPrefix
	if prefix == "" {
		prefix = defaultKeyPrefix
	}
	clk := opts.Clock
	if clk == nil {
		clk = realClock{}
	}
	idg := opts.IDGen
	if idg == nil {
		idg = cryptoIDGen{}
	}
	return &Service{
		rdb:    opts.Redis,
		prefix: prefix,
		clock:  clk,
		idGen:  idg,
	}, nil
}

// ValidateRules 校验 ADR 稳定值。
func ValidateRules(rk RoundKind, gm GameMode) error {
	switch rk {
	case RoundKindEast, RoundKindHanchan:
	default:
		return fmt.Errorf("%w: round_kind", ErrInvalidRules)
	}
	switch gm {
	case GameModeStandard, GameModeTrashTalk:
	default:
		return fmt.Errorf("%w: game_mode", ErrInvalidRules)
	}
	return nil
}

func (s *Service) ticketKey(id string) string {
	return s.prefix + "ticket:" + id
}

func (s *Service) guestKey(guestID string, rk RoundKind, gm GameMode) string {
	return s.prefix + "guest:" + guestID + ":" + string(rk) + ":" + string(gm)
}

func (s *Service) poolKey(rk RoundKind, gm GameMode) string {
	return s.prefix + "pool:" + string(rk) + ":" + string(gm)
}

// enqueueScript 原子幂等入队：
// 1) guest 索引已指向 waiting ticket → 返回既有 id
// 2) 否则写入新 ticket、更新 guest 索引、ZADD 匹配池
// Redis 串行执行 Lua，并发同 guest+规则收敛为同一 ticket。
var enqueueScript = redis.NewScript(`
local gkey = KEYS[1]
local tkey = KEYS[2]
local pkey = KEYS[3]
local ticket_prefix = ARGV[1]
local ticket_id = ARGV[2]
local guest_id = ARGV[3]
local round_kind = ARGV[4]
local game_mode = ARGV[5]
local status = ARGV[6]
local queued_at = ARGV[7]
local deadline_at = ARGV[8]
local score = ARGV[9]
local ttl = tonumber(ARGV[10])

local existing = redis.call('GET', gkey)
if existing then
  local etkey = ticket_prefix .. existing
  local estatus = redis.call('HGET', etkey, 'status')
  if estatus == 'waiting' then
    return {'EXISTING', existing}
  end
end

redis.call('SET', gkey, ticket_id, 'EX', ttl)
-- 完整替换 ticket 哈希，避免同 id 复用时残留 room/seat/token 半状态字段。
redis.call('DEL', tkey)
redis.call('HSET', tkey,
  'ticket_id', ticket_id,
  'guest_id', guest_id,
  'round_kind', round_kind,
  'game_mode', game_mode,
  'status', status,
  'queued_at', queued_at,
  'deadline_at', deadline_at)
redis.call('EXPIRE', tkey, ttl)
redis.call('ZADD', pkey, score, ticket_id)
return {'CREATED', ticket_id}
`)

// cancelScript 原子取消：与 match 消费互斥。
// - waiting → cancelled + ZREM + 清 guest 索引
// - cancelled → 幂等 OK
// - assigned → 不得改写，返回 ASSIGNED（调用方回读终态）
var cancelScript = redis.NewScript(`
local tkey = KEYS[1]
local gkey = KEYS[2]
local pkey = KEYS[3]
local guest_id = ARGV[1]

if redis.call('EXISTS', tkey) == 0 then
  return {'NOT_FOUND'}
end
local owner = redis.call('HGET', tkey, 'guest_id')
if owner ~= guest_id then
  return {'FORBIDDEN'}
end
local tid = redis.call('HGET', tkey, 'ticket_id')
local status = redis.call('HGET', tkey, 'status')
if status == 'assigned' then
  redis.call('ZREM', pkey, tid)
  return {'ASSIGNED'}
end
if status == 'cancelled' then
  redis.call('ZREM', pkey, tid)
  return {'OK'}
end
if status ~= 'waiting' then
  return {'OK'}
end
redis.call('HSET', tkey, 'status', 'cancelled')
redis.call('ZREM', pkey, tid)
local cur = redis.call('GET', gkey)
if cur == tid then
  redis.call('DEL', gkey)
end
return {'OK'}
`)

// Enqueue 加入队列；同 guest+规则组合 waiting 时幂等返回同一 ticket。
func (s *Service) Enqueue(ctx context.Context, guestID string, rk RoundKind, gm GameMode) (Ticket, error) {
	if guestID == "" {
		return Ticket{}, fmt.Errorf("guest_id required")
	}
	if err := ValidateRules(rk, gm); err != nil {
		return Ticket{}, err
	}

	ticketID, err := s.idGen.NewID()
	if err != nil {
		return Ticket{}, err
	}
	// 毫秒精度：业务 30s 边界与 Redis score / queued_at 同源，避免整秒截断提前匹配。
	now := time.UnixMilli(s.clock.Now().UTC().UnixMilli()).UTC()
	deadline := now.Add(QueueWaitDeadline)

	res, err := enqueueScript.Run(ctx, s.rdb, []string{
		s.guestKey(guestID, rk, gm),
		s.ticketKey(ticketID),
		s.poolKey(rk, gm),
	},
		s.prefix+"ticket:",
		ticketID,
		guestID,
		string(rk),
		string(gm),
		StatusWaiting,
		formatTicketTime(now),
		formatTicketTime(deadline),
		fmt.Sprintf("%d", now.UnixMilli()),
		int(ticketTTL.Seconds()),
	).Result()
	if err != nil {
		return Ticket{}, err
	}

	arr, ok := res.([]interface{})
	if !ok || len(arr) != 2 {
		return Ticket{}, fmt.Errorf("unexpected enqueue script result: %v", res)
	}
	id, _ := arr[1].(string)
	return s.loadTicket(ctx, id)
}

// Get 查询 ticket；仅所属 guest 可查。
func (s *Service) Get(ctx context.Context, guestID, ticketID string) (Ticket, error) {
	tk, err := s.loadTicket(ctx, ticketID)
	if err != nil {
		return Ticket{}, err
	}
	if tk.GuestID != guestID {
		return Ticket{}, ErrForbidden
	}
	return tk, nil
}

// Cancel 取消排队；原子移出匹配池；重复取消幂等。
func (s *Service) Cancel(ctx context.Context, guestID, ticketID string) (Ticket, error) {
	// 先读以构造 pool/guest key（脚本内再次校验属主，避免 TOCTOU 越权取消）
	tk, err := s.loadTicket(ctx, ticketID)
	if err != nil {
		return Ticket{}, err
	}
	if tk.GuestID != guestID {
		return Ticket{}, ErrForbidden
	}

	res, err := cancelScript.Run(ctx, s.rdb, []string{
		s.ticketKey(ticketID),
		s.guestKey(guestID, tk.RoundKind, tk.GameMode),
		s.poolKey(tk.RoundKind, tk.GameMode),
	}, guestID).Result()
	if err != nil {
		return Ticket{}, err
	}
	arr, ok := res.([]interface{})
	if !ok || len(arr) < 1 {
		return Ticket{}, fmt.Errorf("unexpected cancel result: %v", res)
	}
	switch arr[0].(string) {
	case "NOT_FOUND":
		return Ticket{}, ErrNotFound
	case "FORBIDDEN":
		return Ticket{}, ErrForbidden
	case "OK", "ASSIGNED":
		// OK=已取消（或幂等）；ASSIGNED=消费已胜出，返回实际终态且不得变 cancelled。
		return s.loadTicket(ctx, ticketID)
	default:
		return Ticket{}, fmt.Errorf("unexpected cancel kind: %v", arr[0])
	}
}

// IsInPool 报告 ticket 是否在其规则池中。
func (s *Service) IsInPool(ctx context.Context, tk Ticket) bool {
	return s.IsMemberOfPool(ctx, tk.RoundKind, tk.GameMode, tk.TicketID)
}

// IsMemberOfPool 报告 ticket_id 是否在指定池。
func (s *Service) IsMemberOfPool(ctx context.Context, rk RoundKind, gm GameMode, ticketID string) bool {
	_, err := s.rdb.ZScore(ctx, s.poolKey(rk, gm), ticketID).Result()
	return err == nil
}

// IsConsumable waiting 且仍在匹配池中（供未来 #239 消费门控；取消后必须为 false）。
func (s *Service) IsConsumable(ctx context.Context, ticketID string) bool {
	tk, err := s.loadTicket(ctx, ticketID)
	if err != nil {
		return false
	}
	if tk.Status != StatusWaiting {
		return false
	}
	return s.IsInPool(ctx, tk)
}

func (s *Service) loadTicket(ctx context.Context, ticketID string) (Ticket, error) {
	if ticketID == "" {
		return Ticket{}, ErrNotFound
	}
	m, err := s.rdb.HGetAll(ctx, s.ticketKey(ticketID)).Result()
	if err != nil {
		return Ticket{}, err
	}
	if len(m) == 0 {
		return Ticket{}, ErrNotFound
	}
	queuedAt, err := parseTicketTime(m["queued_at"])
	if err != nil {
		return Ticket{}, fmt.Errorf("corrupt queued_at: %w", err)
	}
	deadlineAt, err := parseTicketTime(m["deadline_at"])
	if err != nil {
		return Ticket{}, fmt.Errorf("corrupt deadline_at: %w", err)
	}
	tk := Ticket{
		TicketID:   m["ticket_id"],
		GuestID:    m["guest_id"],
		RoundKind:  RoundKind(m["round_kind"]),
		GameMode:   GameMode(m["game_mode"]),
		Status:     m["status"],
		QueuedAt:   TicketTime(queuedAt.UTC()),
		DeadlineAt: TicketTime(deadlineAt.UTC()),
		RoomID:     m["room_id"],
		Worker:     m["worker"],
		RoomToken:  m["room_token"],
	}
	if rawSeat, ok := m["seat"]; ok && rawSeat != "" {
		seat, err := strconv.Atoi(rawSeat)
		if err != nil {
			return Ticket{}, fmt.Errorf("corrupt seat: %w", err)
		}
		tk.Seat = seat
		tk.HasSeat = true
	}
	return tk, nil
}

// formatTicketTime 持久化与 HTTP 共用：整秒用 RFC3339，亚秒保留到毫秒。
func formatTicketTime(t time.Time) string {
	t = t.UTC()
	if t.Nanosecond() == 0 {
		return t.Format(time.RFC3339)
	}
	return t.Format("2006-01-02T15:04:05.000Z07:00")
}

func parseTicketTime(s string) (time.Time, error) {
	if s == "" {
		return time.Time{}, fmt.Errorf("empty time")
	}
	if t, err := time.Parse(time.RFC3339Nano, s); err == nil {
		return t.UTC(), nil
	}
	t, err := time.Parse(time.RFC3339, s)
	if err != nil {
		return time.Time{}, err
	}
	return t.UTC(), nil
}
