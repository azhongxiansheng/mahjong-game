package httpserver

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"
)

func TestCasualQueue_EnqueueRequiresCharacterID(t *testing.T) {
	baseURL, ts, _ := newQueueServer(t)
	_, token := issueGuestToken(t, ts)

	// 缺 character_id
	resp, raw := doJSON(t, http.MethodPost, baseURL+"/v1/queues/casual", token,
		[]byte(`{"round_kind":"EAST","game_mode":"STANDARD"}`))
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("missing char status=%d body=%s", resp.StatusCode, redactSecrets(raw))
	}
	if strings.Contains(raw, "room_token") || strings.Contains(strings.ToLower(raw), "secret") {
		t.Fatalf("error must not leak token: %s", redactSecrets(raw))
	}

	// ability_id 等未知字段拒绝
	resp2, raw2 := doJSON(t, http.MethodPost, baseURL+"/v1/queues/casual", token,
		[]byte(`{"round_kind":"EAST","game_mode":"STANDARD","character_id":"lin_yeche","ability_id":"x"}`))
	if resp2.StatusCode != http.StatusBadRequest {
		t.Fatalf("extra field status=%d body=%s", resp2.StatusCode, redactSecrets(raw2))
	}

	// 成功路径回显 character_id，不泄露 token（waiting 无 room_token）
	resp3, raw3 := doJSON(t, http.MethodPost, baseURL+"/v1/queues/casual", token,
		[]byte(`{"round_kind":"EAST","game_mode":"STANDARD","character_id":"lin_yeche"}`))
	if resp3.StatusCode != http.StatusOK {
		t.Fatalf("ok status=%d body=%s", resp3.StatusCode, redactSecrets(raw3))
	}
	var join map[string]any
	if err := json.Unmarshal([]byte(raw3), &join); err != nil {
		t.Fatal(err)
	}
	if join["character_id"] != "lin_yeche" {
		t.Fatalf("character_id=%v", join["character_id"])
	}
	if _, ok := join["room_token"]; ok {
		t.Fatal("waiting must not include room_token")
	}
}
