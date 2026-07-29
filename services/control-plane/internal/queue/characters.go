package queue

import (
	"fmt"
)

// CanonicalCharacterIDs 冻结角色目录（与 Godot CharacterPool id 一致，字典序）。
// 权威端 AI 补齐与入队校验共用；不得在客户端复制业务能力逻辑。
var CanonicalCharacterIDs = []string{
	"an_cheng",
	"bai_touli",
	"bao_luo",
	"hua_ling",
	"ji_shu",
	"ju_jin",
	"lian_yao",
	"lin_yeche",
	"qiu_jue",
	"xian_shi",
	"ying_li",
	"yuan_xi",
}

var canonicalCharacterSet map[string]struct{}

func init() {
	canonicalCharacterSet = make(map[string]struct{}, len(CanonicalCharacterIDs))
	for _, id := range CanonicalCharacterIDs {
		canonicalCharacterSet[id] = struct{}{}
	}
}

// ErrInvalidCharacter 非法或未知 character_id。
var ErrInvalidCharacter = fmt.Errorf("invalid character_id")

// IsCanonicalCharacterID 报告 id 是否在冻结目录内。
func IsCanonicalCharacterID(id string) bool {
	if id == "" {
		return false
	}
	_, ok := canonicalCharacterSet[id]
	return ok
}

// ValidateCharacterID 入队/roster 门控。
func ValidateCharacterID(id string) error {
	if !IsCanonicalCharacterID(id) {
		return fmt.Errorf("%w: %q", ErrInvalidCharacter, id)
	}
	return nil
}

// BuildCharacterRoster 构造四席不可篡改角色身份。
// HUMAN 席使用 humanBySeat 中的规范 ID（允许重复）；AI 席按席位顺序取
// 冻结目录中尚未占用的首个 ID；若目录耗尽则按 seat 循环取目录项。
// participants 必须恰 4 席 HUMAN|AI。
func BuildCharacterRoster(participants []string, humanBySeat map[int]string) ([]string, error) {
	if len(participants) != 4 {
		return nil, fmt.Errorf("participants must have length 4")
	}
	if humanBySeat == nil {
		humanBySeat = map[int]string{}
	}
	used := make(map[string]struct{}, 4)
	out := make([]string, 4)
	for seat := 0; seat < 4; seat++ {
		switch participants[seat] {
		case SeatKindHuman:
			cid, ok := humanBySeat[seat]
			if !ok {
				return nil, fmt.Errorf("missing human character at seat %d", seat)
			}
			if err := ValidateCharacterID(cid); err != nil {
				return nil, err
			}
			out[seat] = cid
			used[cid] = struct{}{}
		case SeatKindAI:
			// 占位，第二遍填充
			out[seat] = ""
		default:
			return nil, fmt.Errorf("invalid participant kind at seat %d", seat)
		}
	}
	// AI 补齐：确定性、与 room/seed 无关；仅依赖席位顺序与已占用集合。
	for seat := 0; seat < 4; seat++ {
		if participants[seat] != SeatKindAI {
			continue
		}
		picked := ""
		for _, id := range CanonicalCharacterIDs {
			if _, hit := used[id]; !hit {
				picked = id
				break
			}
		}
		if picked == "" {
			// 目录全占用时仍确定性：按 seat 取目录项
			picked = CanonicalCharacterIDs[seat%len(CanonicalCharacterIDs)]
		}
		out[seat] = picked
		used[picked] = struct{}{}
	}
	return out, nil
}
