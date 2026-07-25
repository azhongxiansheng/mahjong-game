extends GutTest

# E4-04 / #246：字幕纯状态模型 — 中英日、ADR kind、partial/final、revision、TTL、幂等。

const ModelScr := preload("res://ui/four_player_table/seat_caption_model.gd")

const T0 := 1_000_000


func _base(overrides: Dictionary = {}) -> Dictionary:
	var d := {
		"seat": 0,
		"utterance_id": "utt_a",
		"text": "你好",
		"kind": "partial",
		"source": "local_mic",
		"lang": "zh",
		"now_ms": T0,
	}
	for k in overrides.keys():
		d[k] = overrides[k]
	return d


func test_accepts_zh_en_ja_and_preserves_unicode() -> void:
	var m = ModelScr.new()
	var zh: Dictionary = m.ingest(_base({"text": "听牌了吗？", "lang": "zh"}))
	assert_true(bool(zh.get("ok", false)), str(zh))
	assert_eq(String(m.display_for_seat(0).get("text", "")), "听牌了吗？")

	var en: Dictionary = m.ingest(_base({
		"seat": 1, "utterance_id": "utt_en", "text": "I tenpai", "lang": "en",
	}))
	assert_true(bool(en.get("ok", false)), str(en))
	assert_eq(String(m.display_for_seat(1).get("text", "")), "I tenpai")

	var ja: Dictionary = m.ingest(_base({
		"seat": 2, "utterance_id": "utt_ja", "text": "リーチ！", "lang": "ja",
		"source": "server_stt", "kind": "final",
	}))
	assert_true(bool(ja.get("ok", false)), str(ja))
	assert_eq(String(m.display_for_seat(2).get("text", "")), "リーチ！")
	assert_eq(String(m.display_for_seat(2).get("lang", "")), "ja")

	var via_language: Dictionary = m.ingest({
		"seat": 3, "utterance_id": "utt_lang_key", "text": "Hello",
		"kind": "final", "source": "ai_text", "language": "en", "now_ms": T0,
	})
	assert_true(bool(via_language.get("ok", false)), str(via_language))
	assert_eq(String(m.display_for_seat(3).get("lang", "")), "en")


func test_source_labels_and_ai_never_mic() -> void:
	var m = ModelScr.new()
	assert_eq(ModelScr.source_label("local_mic"), "本地麦克风")
	assert_eq(ModelScr.source_label("server_stt"), "服务端转写")
	assert_eq(ModelScr.source_label("faster_whisper"), "服务端转写")
	assert_eq(ModelScr.source_label("ai_text"), "AI 文本")
	assert_eq(ModelScr.lang_label("zh"), "中")
	assert_eq(ModelScr.lang_label("en"), "EN")
	assert_eq(ModelScr.lang_label("ja"), "日")
	assert_eq(ModelScr.header_text(2, "服务端转写", "ja"), "座位 2｜服务端转写｜日")

	var ai: Dictionary = m.ingest(_base({
		"seat": 3, "utterance_id": "ai|w|3", "text": "面白いね",
		"kind": "final", "source": "ai_text", "lang": "ja",
	}))
	assert_true(bool(ai.get("ok", false)), str(ai))
	var d: Dictionary = m.display_for_seat(3)
	assert_eq(String(d.get("source_label", "")), "AI 文本")
	assert_false(String(d.get("source_label", "")).contains("麦克"))
	assert_false(String(d.get("source", "")).contains("mic"))
	assert_false(bool(d.get("is_mic", true)))
	assert_true(String(d.get("header", "")).contains("AI 文本"))
	assert_true(String(d.get("header", "")).contains("日"))


func test_adr_transcript_kinds_normalize() -> void:
	var m = ModelScr.new()
	var partial: Dictionary = m.ingest({
		"protocol_version": 1,
		"room_id": "room_x",
		"seat": 0,
		"kind": "TRANSCRIPT_PARTIAL",
		"utterance_id": "utt_1",
		"text": "例",
		"lang": "zh",
		"source": "faster_whisper",
		"now_ms": T0,
	})
	assert_true(bool(partial.get("ok", false)), str(partial))
	assert_eq(String(m.display_for_seat(0).get("kind", "")), "partial")
	assert_eq(String(m.display_for_seat(0).get("source", "")), "server_stt")

	var fin: Dictionary = m.ingest({
		"protocol_version": 1,
		"room_id": "room_x",
		"seat": 0,
		"kind": "TRANSCRIPT_FINAL",
		"utterance_id": "utt_1",
		"text": "例子",
		"lang": "zh",
		"source": "faster_whisper",
		"now_ms": T0 + 50,
	})
	assert_true(bool(fin.get("ok", false)), str(fin))
	assert_eq(String(m.display_for_seat(0).get("kind", "")), "final")
	assert_eq(String(m.display_for_seat(0).get("text", "")), "例子")

	var late: Dictionary = m.ingest({
		"protocol_version": 1,
		"room_id": "room_x",
		"seat": 0,
		"kind": "TRANSCRIPT_PARTIAL",
		"utterance_id": "utt_1",
		"text": "例",
		"lang": "zh",
		"source": "faster_whisper",
		"now_ms": T0 + 60,
	})
	assert_false(bool(late.get("ok", false)))
	assert_eq(String(late.get("reason", "")), "AFTER_FINAL")

	var dup: Dictionary = m.ingest({
		"protocol_version": 1,
		"room_id": "room_x",
		"seat": 0,
		"kind": "TRANSCRIPT_FINAL",
		"utterance_id": "utt_1",
		"text": "例子",
		"lang": "zh",
		"source": "faster_whisper",
		"now_ms": T0 + 100,
	})
	assert_true(bool(dup.get("ok", false)))
	assert_true(bool(dup.get("idempotent", false)))

	# 低 revision partial on new utt
	assert_true(bool(m.ingest({
		"protocol_version": 1, "room_id": "room_x", "seat": 1,
		"kind": "TRANSCRIPT_PARTIAL", "utterance_id": "utt_rev",
		"text": "r2", "lang": "en", "source": "faster_whisper",
		"display_revision": 2, "now_ms": T0,
	}).get("ok", false)))
	var low: Dictionary = m.ingest({
		"protocol_version": 1, "room_id": "room_x", "seat": 1,
		"kind": "TRANSCRIPT_PARTIAL", "utterance_id": "utt_rev",
		"text": "r1", "lang": "en", "source": "faster_whisper",
		"display_revision": 1, "now_ms": T0 + 1,
	})
	assert_false(bool(low.get("ok", false)))
	assert_eq(String(low.get("reason", "")), "STALE_REVISION")


func test_partial_replaced_by_final_same_utterance() -> void:
	var m = ModelScr.new()
	assert_true(bool(m.ingest(_base({"text": "听…", "kind": "partial"})).get("ok", false)))
	assert_eq(String(m.display_for_seat(0).get("kind", "")), "partial")
	assert_true(bool(m.ingest(_base({
		"text": "听牌", "kind": "final", "now_ms": T0 + 100,
	})).get("ok", false)))
	var d: Dictionary = m.display_for_seat(0)
	assert_eq(String(d.get("kind", "")), "final")
	assert_eq(String(d.get("text", "")), "听牌")


func test_final_first_then_partial_ignored() -> void:
	var m = ModelScr.new()
	assert_true(bool(m.ingest(_base({
		"text": "完", "kind": "final", "source": "server_stt",
	})).get("ok", false)))
	var late_partial: Dictionary = m.ingest(_base({
		"text": "完…", "kind": "partial", "now_ms": T0 + 50,
	}))
	assert_false(bool(late_partial.get("ok", false)))
	assert_eq(String(m.display_for_seat(0).get("text", "")), "完")
	assert_eq(String(m.display_for_seat(0).get("kind", "")), "final")


func test_lower_revision_partial_rejected() -> void:
	var m = ModelScr.new()
	assert_true(bool(m.ingest(_base({
		"text": "rev2", "kind": "partial", "display_revision": 2,
	})).get("ok", false)))
	var low: Dictionary = m.ingest(_base({
		"text": "rev1", "kind": "partial", "display_revision": 1, "now_ms": T0 + 10,
	}))
	assert_false(bool(low.get("ok", false)))
	assert_eq(String(m.display_for_seat(0).get("text", "")), "rev2")


func test_final_bypasses_lower_partial_display_revision() -> void:
	# P2-1：display_revision 只拒绝旧 partial；final 必须无条件替换同 utterance partial。
	var m = ModelScr.new()
	var partial: Dictionary = m.ingest({
		"protocol_version": 1,
		"room_id": "room_x",
		"seat": 0,
		"kind": "TRANSCRIPT_PARTIAL",
		"utterance_id": "utt_rev_final",
		"text": "部分",
		"lang": "zh",
		"source": "faster_whisper",
		"display_revision": 5,
		"now_ms": T0,
	})
	assert_true(bool(partial.get("ok", false)), str(partial))
	assert_eq(String(m.display_for_seat(0).get("kind", "")), "partial")

	var fin: Dictionary = m.ingest({
		"protocol_version": 1,
		"room_id": "room_x",
		"seat": 0,
		"kind": "TRANSCRIPT_FINAL",
		"utterance_id": "utt_rev_final",
		"text": "最终文本",
		"lang": "zh",
		"source": "faster_whisper",
		"display_revision": 1,
		"now_ms": T0 + 50,
	})
	assert_true(bool(fin.get("ok", false)),
		"final rev=1 不得被 partial rev=5 的 STALE_REVISION 拦截: %s" % str(fin))
	assert_false(bool(fin.get("idempotent", false)))
	var d: Dictionary = m.display_for_seat(0)
	assert_eq(String(d.get("kind", "")), "final")
	assert_eq(String(d.get("text", "")), "最终文本")

	# final 后 partial 仍拒绝；不同 final 仍冲突；重复 final 幂等
	var late_p: Dictionary = m.ingest({
		"protocol_version": 1, "room_id": "room_x", "seat": 0,
		"kind": "TRANSCRIPT_PARTIAL", "utterance_id": "utt_rev_final",
		"text": "迟到", "lang": "zh", "source": "faster_whisper",
		"display_revision": 9, "now_ms": T0 + 60,
	})
	assert_false(bool(late_p.get("ok", false)))
	assert_eq(String(late_p.get("reason", "")), "AFTER_FINAL")
	var conf_f: Dictionary = m.ingest({
		"protocol_version": 1, "room_id": "room_x", "seat": 0,
		"kind": "TRANSCRIPT_FINAL", "utterance_id": "utt_rev_final",
		"text": "另一最终", "lang": "zh", "source": "faster_whisper",
		"display_revision": 2, "now_ms": T0 + 70,
	})
	assert_false(bool(conf_f.get("ok", false)))
	assert_eq(String(conf_f.get("reason", "")), "FINAL_CONFLICT")
	var dup_f: Dictionary = m.ingest({
		"protocol_version": 1, "room_id": "room_x", "seat": 0,
		"kind": "TRANSCRIPT_FINAL", "utterance_id": "utt_rev_final",
		"text": "最终文本", "lang": "zh", "source": "faster_whisper",
		"display_revision": 1, "now_ms": T0 + 80,
	})
	assert_true(bool(dup_f.get("ok", false)))
	assert_true(bool(dup_f.get("idempotent", false)))


func test_same_revision_different_content_rejected() -> void:
	var m = ModelScr.new()
	assert_true(bool(m.ingest(_base({
		"text": "A", "kind": "partial", "display_revision": 5,
	})).get("ok", false)))
	var conf: Dictionary = m.ingest(_base({
		"text": "B", "kind": "partial", "display_revision": 5, "now_ms": T0 + 1,
	}))
	assert_false(bool(conf.get("ok", false)))
	assert_eq(String(conf.get("reason", "")), "REVISION_CONFLICT")
	assert_eq(String(m.display_for_seat(0).get("text", "")), "A")


func test_negative_revision_rejected() -> void:
	var m = ModelScr.new()
	var r: Dictionary = m.ingest(_base({"display_revision": -1}))
	assert_false(bool(r.get("ok", false)))
	assert_eq(String(r.get("reason", "")), "INVALID_REVISION")
	assert_true(m.display_for_seat(0).is_empty())


func test_empty_text_rejected_no_side_effect() -> void:
	var m = ModelScr.new()
	assert_true(bool(m.ingest(_base({"text": "ok"})).get("ok", false)))
	var before: Dictionary = m.display_for_seat(0).duplicate(true)
	for bad in ["", "   ", "\t"]:
		var r: Dictionary = m.ingest(_base({
			"utterance_id": "empty_x", "text": bad, "now_ms": T0 + 1,
		}))
		assert_false(bool(r.get("ok", false)), "空 text 应拒绝: %s" % str(bad))
	assert_eq(
		TrashTalkGoldFixtures.stable_stringify(m.display_for_seat(0)),
		TrashTalkGoldFixtures.stable_stringify(before)
	)


func test_exact_duplicate_partial_and_final_are_idempotent_no_ttl_refresh() -> void:
	var m = ModelScr.new()
	assert_true(bool(m.ingest(_base({
		"text": "dup", "kind": "partial", "now_ms": T0,
	})).get("ok", false)))
	var exp1: int = int(m.display_for_seat(0).get("expires_at_ms", -1))
	var again: Dictionary = m.ingest(_base({
		"text": "dup", "kind": "partial", "now_ms": T0 + 500,
	}))
	assert_true(bool(again.get("ok", false)))
	assert_true(bool(again.get("idempotent", false)))
	assert_eq(int(m.display_for_seat(0).get("expires_at_ms", -1)), exp1)

	assert_true(bool(m.ingest(_base({
		"text": "dupF", "kind": "final", "now_ms": T0 + 600,
	})).get("ok", false)))
	var exp_f: int = int(m.display_for_seat(0).get("expires_at_ms", -1))
	var again_f: Dictionary = m.ingest(_base({
		"text": "dupF", "kind": "final", "now_ms": T0 + 2000,
	}))
	assert_true(bool(again_f.get("ok", false)))
	assert_true(bool(again_f.get("idempotent", false)))
	assert_eq(int(m.display_for_seat(0).get("expires_at_ms", -1)), exp_f)


func test_ttl_partial_3s_final_5s_deterministic() -> void:
	var m = ModelScr.new()
	assert_true(bool(m.ingest(_base({
		"text": "p", "kind": "partial", "now_ms": T0,
	})).get("ok", false)))
	assert_true(m.has_visible_for_seat(0, T0 + 2999))
	assert_false(m.has_visible_for_seat(0, T0 + 3000))
	m.tick(T0 + 3000)
	assert_true(m.display_for_seat(0).is_empty())

	assert_true(bool(m.ingest(_base({
		"utterance_id": "utt_f", "text": "f", "kind": "final",
		"source": "server_stt", "now_ms": T0 + 4000,
	})).get("ok", false)))
	assert_true(m.has_visible_for_seat(0, T0 + 4000 + 4999))
	assert_false(m.has_visible_for_seat(0, T0 + 4000 + 5000))

	assert_true(bool(m.ingest(_base({
		"seat": 1, "utterance_id": "ai1", "text": "ai", "kind": "final",
		"source": "ai_text", "now_ms": T0, "language": "en",
	})).get("ok", false)))
	assert_true(m.has_visible_for_seat(1, T0 + 4999))
	assert_false(m.has_visible_for_seat(1, T0 + 5000))


func test_late_after_expiry_is_safe() -> void:
	var m = ModelScr.new()
	assert_true(bool(m.ingest(_base({
		"text": "gone", "kind": "partial", "now_ms": T0,
	})).get("ok", false)))
	m.tick(T0 + 3000)
	assert_true(m.display_for_seat(0).is_empty())
	var late: Dictionary = m.ingest(_base({
		"text": "gone", "kind": "partial", "now_ms": T0 + 3100,
	}))
	assert_true(bool(late.get("ok", false)))
	assert_true(bool(late.get("idempotent", false)))
	assert_true(m.display_for_seat(0).is_empty())


func test_different_utterances_independent() -> void:
	var m = ModelScr.new()
	assert_true(bool(m.ingest(_base({
		"seat": 0, "utterance_id": "u0", "text": "A",
	})).get("ok", false)))
	assert_true(bool(m.ingest(_base({
		"seat": 1, "utterance_id": "u1", "text": "B", "source": "server_stt",
	})).get("ok", false)))
	assert_eq(String(m.display_for_seat(0).get("text", "")), "A")
	assert_eq(String(m.display_for_seat(1).get("text", "")), "B")
	assert_true(bool(m.ingest(_base({
		"seat": 0, "utterance_id": "u0", "text": "A-final", "kind": "final",
		"now_ms": T0 + 10,
	})).get("ok", false)))
	assert_eq(String(m.display_for_seat(1).get("text", "")), "B")


func test_malformed_and_unknown_fields_rejected_zero_side_effect() -> void:
	var m = ModelScr.new()
	assert_true(bool(m.ingest(_base({})).get("ok", false)))
	var before: Dictionary = m.display_for_seat(0).duplicate(true)

	var bad_cases: Array = [
		{},
		{"seat": 9, "utterance_id": "x", "text": "t", "kind": "partial",
			"source": "local_mic", "lang": "zh", "now_ms": T0},
		{"seat": 0, "utterance_id": "", "text": "t", "kind": "partial",
			"source": "local_mic", "lang": "zh", "now_ms": T0},
		{"seat": 0, "utterance_id": "x", "text": "t", "kind": "maybe",
			"source": "local_mic", "lang": "zh", "now_ms": T0},
		{"seat": 0, "utterance_id": "x", "text": "t", "kind": "partial",
			"source": "unknown_src", "lang": "zh", "now_ms": T0},
		{"seat": 0, "utterance_id": "x", "text": "t", "kind": "partial",
			"source": "local_mic", "lang": "ko", "now_ms": T0},
		{"seat": 0, "utterance_id": "x", "text": 123, "kind": "partial",
			"source": "local_mic", "lang": "zh", "now_ms": T0},
	]
	for c in bad_cases:
		var r: Dictionary = m.ingest(c)
		assert_false(bool(r.get("ok", false)), "应拒绝: %s" % str(c))
	assert_eq(
		TrashTalkGoldFixtures.stable_stringify(m.display_for_seat(0)),
		TrashTalkGoldFixtures.stable_stringify(before),
		"拒绝后零副作用"
	)


func test_caption_ingest_never_emits_reward_kinds() -> void:
	var m = ModelScr.new()
	var r: Dictionary = m.ingest(_base({"kind": "final", "source": "local_mic"}))
	assert_true(bool(r.get("ok", false)))
	assert_false(r.has("ITEM_GRANTED"))
	for k in r.keys():
		assert_false(String(k).begins_with("REWARD_WINDOW"), str(k))
	assert_true(m.side_effect_event_kinds().is_empty())
