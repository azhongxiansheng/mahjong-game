from __future__ import annotations

from stt_service.config import SttConfig
from stt_service.session import Phase, SessionManager, gen_key
from stt_service.transcriber import TranscribeResult, WhisperTranscriber


class FakeTx(WhisperTranscriber):
    def __init__(self):
        super().__init__(SttConfig())

    def ensure_model(self):
        return object()

    def transcribe_pcm(self, pcm: bytes, *, is_final: bool) -> TranscribeResult:
        if not pcm or len(pcm) < 100:
            return TranscribeResult("", "", 0.0, 0.0, 1, "EMPTY")
        return TranscribeResult("hello world", "en", 1.0, 0.9, 5, None)


def _cfg(**kwargs) -> SttConfig:
    base = dict(max_pcm_bytes=2000, max_utterance_ms=1000, max_active_utterances=2, partial_interval_ms=0)
    base.update(kwargs)
    return SttConfig(**base)


def test_overflow_releases():
    sm = SessionManager(_cfg(), FakeTx())
    sm.start({"room_id": "r", "seat": 0, "hand_seq": 1, "window_id": "w1", "utterance_id": "u1"}, conn_id=1)
    err = sm.append_b64("r", 0, "u1", __import__("base64").b64encode(b"\x00\x01" * 2000).decode(), hand_seq=1, window_id="w1", conn_id=1)
    assert err == "OVERFLOW"
    assert sm.active_count() == 0


def test_window_cancel_room_and_hand_scoped():
    sm = SessionManager(_cfg(max_pcm_bytes=100000, max_active_utterances=8), FakeTx())
    s1, e1 = sm.start({"room_id": "roomA", "seat": 0, "hand_seq": 0, "window_id": "same", "utterance_id": "uA"}, 1)
    s2, e2 = sm.start({"room_id": "roomB", "seat": 0, "hand_seq": 0, "window_id": "same", "utterance_id": "uB"}, 2)
    s3, e3 = sm.start({"room_id": "roomA", "seat": 1, "hand_seq": 1, "window_id": "same", "utterance_id": "uA2"}, 1)
    assert e1 is None and e2 is None and e3 is None
    b64 = __import__("base64").b64encode(b"\x00\x01" * 200).decode()
    sm.append_b64("roomA", 0, "uA", b64, hand_seq=0, window_id="same", conn_id=1)
    sm.append_b64("roomB", 0, "uB", b64, hand_seq=0, window_id="same", conn_id=2)
    sm.append_b64("roomA", 1, "uA2", b64, hand_seq=1, window_id="same", conn_id=1)
    failed = sm.cancel_window("roomA", 0, "same")
    assert len(failed) == 1
    assert failed[0]["room_id"] == "roomA"
    assert sm.active_count() == 2  # roomB hand0 + roomA hand1
    assert gen_key("roomA", 0, "same") in sm._cancelled_gens


def test_no_partial_after_commit():
    sm = SessionManager(_cfg(max_pcm_bytes=100000, partial_interval_ms=0), FakeTx())
    sm.start({"room_id": "r", "seat": 0, "hand_seq": 0, "window_id": "w", "utterance_id": "u"}, 1)
    # >= 10 frames * 640 bytes for partial threshold
    b64 = __import__("base64").b64encode(b"\x00\x10" * (640 * 12 // 2)).decode()
    assert sm.append_b64("r", 0, "u", b64, hand_seq=0, window_id="w", conn_id=1) is None
    pcm, token, sess, err = sm.begin_partial("r", 0, "u")
    assert err is None and pcm
    # commit while partial "running"
    meta = {"room_id": "r", "seat": 0, "hand_seq": 0, "window_id": "w", "utterance_id": "u", "ptt_end_server_seq": 5}
    pcm2, token2, s2, early = sm.begin_commit(meta, 1)
    assert early is None and pcm2 is not None
    # partial end must drop
    out = sm.end_partial("r", 0, "u", token, "late partial", "en")
    assert out is None
    final = sm.finish_commit(meta, token2, FakeTx().transcribe_pcm(pcm2, is_final=True))
    assert final["kind"] == "TRANSCRIPT_FINAL"


def test_cancel_drops_late_commit():
    sm = SessionManager(_cfg(max_pcm_bytes=100000), FakeTx())
    sm.start({"room_id": "r", "seat": 0, "hand_seq": 0, "window_id": "w", "utterance_id": "u"}, 1)
    b64 = __import__("base64").b64encode(b"\x00\x10" * 200).decode()
    sm.append_b64("r", 0, "u", b64, hand_seq=0, window_id="w", conn_id=1)
    meta = {"room_id": "r", "seat": 0, "hand_seq": 0, "window_id": "w", "utterance_id": "u", "ptt_end_server_seq": 3}
    pcm, token, s, early = sm.begin_commit(meta, 1)
    assert early is None
    sm.cancel_window("r", 0, "w")
    out = sm.finish_commit(meta, token, FakeTx().transcribe_pcm(pcm or b"\x00\x10" * 200, is_final=True))
    assert out["kind"] == "UTTERANCE_FAILED"
    assert out["reason"] == "CANCELLED"


def test_release_connection():
    sm = SessionManager(_cfg(max_pcm_bytes=100000), FakeTx())
    sm.start({"room_id": "r1", "seat": 0, "hand_seq": 0, "window_id": "w", "utterance_id": "u1"}, 10)
    sm.start({"room_id": "r2", "seat": 1, "hand_seq": 0, "window_id": "w", "utterance_id": "u2"}, 20)
    b64 = __import__("base64").b64encode(b"\x00\x01" * 50).decode()
    sm.append_b64("r1", 0, "u1", b64, hand_seq=0, window_id="w", conn_id=10)
    sm.append_b64("r2", 1, "u2", b64, hand_seq=0, window_id="w", conn_id=20)
    sm.release_connection(10)
    assert sm.active_count() == 1


def test_strict_float_rejected_by_protocol():
    from stt_service.protocol import validate_commit

    meta, err = validate_commit(
        {
            "protocol_version": 1,
            "kind": "UTTERANCE_COMMIT",
            "room_id": "r",
            "seat": 0,
            "hand_seq": 1.0,  # float
            "window_id": "w",
            "utterance_id": "u",
            "ptt_end_server_seq": 1,
        }
    )
    assert meta is None
    assert err == "INVALID_HAND_SEQ"


def test_inflight_released_on_abort():
    sm = SessionManager(_cfg(max_pcm_bytes=100000, partial_interval_ms=0), FakeTx())
    sm.start({"room_id": "r", "seat": 0, "hand_seq": 0, "window_id": "w", "utterance_id": "u"}, 1)
    b64 = __import__("base64").b64encode(b"\x00\x10" * (640 * 12 // 2)).decode()
    sm.append_b64("r", 0, "u", b64, hand_seq=0, window_id="w", conn_id=1)
    pcm, token, sess, err = sm.begin_partial("r", 0, "u")
    assert err is None
    assert sm._global_infer_inflight == 1
    sm.abort_infer_slot()
    sm.force_partial_idle("r", 0, "u")
    assert sm._global_infer_inflight == 0
    # can begin again
    pcm2, t2, s2, e2 = sm.begin_partial("r", 0, "u")
    assert e2 is None


def test_duplicate_commit_same_ptt_cached():
    sm = SessionManager(_cfg(max_pcm_bytes=100000), FakeTx())
    sm.start({"room_id": "r", "seat": 0, "hand_seq": 0, "window_id": "w", "utterance_id": "u"}, 1)
    b64 = __import__("base64").b64encode(b"\x00\x10" * 200).decode()
    sm.append_b64("r", 0, "u", b64, hand_seq=0, window_id="w", conn_id=1)
    meta = {"room_id": "r", "seat": 0, "hand_seq": 0, "window_id": "w", "utterance_id": "u", "ptt_end_server_seq": 9}
    pcm, token, s, early = sm.begin_commit(meta, 1)
    final = sm.finish_commit(meta, token, FakeTx().transcribe_pcm(pcm, is_final=True))
    assert final["kind"] == "TRANSCRIPT_FINAL"
    # second commit same ptt returns cache
    pcm2, t2, s2, early2 = sm.begin_commit(meta, 1)
    assert early2 is not None and early2["kind"] == "TRANSCRIPT_FINAL"


def test_cancel_tombstones_bounded():
    sm = SessionManager(_cfg(max_pcm_bytes=100000, max_active_utterances=8), FakeTx())
    limit = sm._max_cancel_tombstones
    for i in range(limit + 30):
        sm.cancel_window("r", i, f"w{i}")
    assert len(sm._cancelled_gens) <= limit
    assert len(sm._cancel_order) <= limit
    # 淘汰后迟到结果仍靠无 active 丢弃
    assert gen_key("r", 0, "w0") not in sm._cancelled_gens
    assert gen_key("r", limit + 29, f"w{limit + 29}") in sm._cancelled_gens


def test_too_many_infer_releases_active():
    """P1-3：overload 释放 active/PCM；重复 commit 稳定；容量恢复后新 utterance 可成功。"""
    sm = SessionManager(_cfg(max_pcm_bytes=100000, max_active_utterances=4), FakeTx())
    sm._max_global_infer = 1
    b64 = __import__("base64").b64encode(b"\x00\x10" * 200).decode()
    # occupy slot with partial
    sm.start({"room_id": "r", "seat": 0, "hand_seq": 0, "window_id": "w", "utterance_id": "hold"}, 1)
    sm.append_b64("r", 0, "hold", __import__("base64").b64encode(b"\x00\x10" * (640 * 12 // 2)).decode(), hand_seq=0, window_id="w", conn_id=1)
    pcm_h, tok_h, s_h, err_h = sm.begin_partial("r", 0, "hold")
    assert err_h is None and sm._global_infer_inflight == 1
    active_before = sm.active_count()
    # second utterance commit hits overload → must release
    sm.start({"room_id": "r", "seat": 1, "hand_seq": 0, "window_id": "w", "utterance_id": "u2"}, 1)
    sm.append_b64("r", 1, "u2", b64, hand_seq=0, window_id="w", conn_id=1)
    meta = {"room_id": "r", "seat": 1, "hand_seq": 0, "window_id": "w", "utterance_id": "u2", "ptt_end_server_seq": 3}
    pcm, token, s, early = sm.begin_commit(meta, 1)
    assert early is not None and early["reason"] == "TOO_MANY_INFER"
    assert sm.active_count() == active_before  # u2 released; hold still active
    assert sm.total_pcm_bytes() < 100000
    # 重复 commit 稳定（缓存），不复活
    pcm2, t2, s2, early2 = sm.begin_commit(meta, 1)
    assert early2 is not None and early2["reason"] == "TOO_MANY_INFER"
    assert sm.active_count() == active_before
    # 释放 hold slot 后新 utterance 可成功
    sm.end_partial("r", 0, "hold", tok_h, "", "")
    sm.cancel_utterance("r", 0, 0, "w", "hold")
    sm.start({"room_id": "r", "seat": 2, "hand_seq": 0, "window_id": "w", "utterance_id": "u3"}, 1)
    sm.append_b64("r", 2, "u3", b64, hand_seq=0, window_id="w", conn_id=1)
    meta3 = {"room_id": "r", "seat": 2, "hand_seq": 0, "window_id": "w", "utterance_id": "u3", "ptt_end_server_seq": 4}
    pcm3, t3, s3, early3 = sm.begin_commit(meta3, 1)
    assert early3 is None and pcm3 is not None
    final = sm.finish_commit(meta3, t3, FakeTx().transcribe_pcm(pcm3, is_final=True))
    assert final["kind"] == "TRANSCRIPT_FINAL"
