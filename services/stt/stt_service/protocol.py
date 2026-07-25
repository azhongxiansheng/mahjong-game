"""Internal WebSocket JSON protocol. Strict types; no float for authority ints."""

from __future__ import annotations

from typing import Any, Mapping

PROTOCOL_VERSION = 1
SOURCE = "faster_whisper"

KIND_UTTERANCE_START = "UTTERANCE_START"
KIND_AUDIO_CHUNK = "AUDIO_CHUNK"
KIND_UTTERANCE_COMMIT = "UTTERANCE_COMMIT"
KIND_UTTERANCE_CANCEL = "UTTERANCE_CANCEL"
KIND_WINDOW_CANCEL = "WINDOW_CANCEL"
KIND_PING = "PING"

KIND_TRANSCRIPT_PARTIAL = "TRANSCRIPT_PARTIAL"
KIND_TRANSCRIPT_FINAL = "TRANSCRIPT_FINAL"
KIND_UTTERANCE_FAILED = "UTTERANCE_FAILED"
KIND_PONG = "PONG"
KIND_ERROR = "ERROR"


def _req_str(d: Mapping[str, Any], key: str) -> str | None:
    v = d.get(key)
    if not isinstance(v, str) or not v.strip():
        return None
    return v.strip()


def _req_int(d: Mapping[str, Any], key: str) -> int | None:
    """Strict: only JSON integers (Python int, not bool/float)."""
    v = d.get(key)
    if type(v) is not int:  # noqa: E721 — bool is subclass of int
        return None
    return v


def validate_start(msg: Mapping[str, Any]) -> tuple[dict[str, Any] | None, str | None]:
    if _req_int(msg, "protocol_version") != PROTOCOL_VERSION:
        return None, "PROTOCOL_VERSION_UNSUPPORTED"
    if str(msg.get("kind", "")) != KIND_UTTERANCE_START:
        return None, "BAD_KIND"
    room_id = _req_str(msg, "room_id")
    window_id = _req_str(msg, "window_id")
    utterance_id = _req_str(msg, "utterance_id")
    seat = _req_int(msg, "seat")
    hand_seq = _req_int(msg, "hand_seq")
    if room_id is None or window_id is None or utterance_id is None:
        return None, "INVALID_IDENTITY"
    if seat is None or seat < 0 or seat > 3:
        return None, "INVALID_SEAT"
    if hand_seq is None or hand_seq < 0:
        return None, "INVALID_HAND_SEQ"
    return {
        "protocol_version": PROTOCOL_VERSION,
        "kind": KIND_UTTERANCE_START,
        "room_id": room_id,
        "seat": seat,
        "hand_seq": hand_seq,
        "window_id": window_id,
        "utterance_id": utterance_id,
    }, None


def validate_chunk(msg: Mapping[str, Any]) -> tuple[dict[str, Any] | None, str | None]:
    if _req_int(msg, "protocol_version") != PROTOCOL_VERSION:
        return None, "PROTOCOL_VERSION_UNSUPPORTED"
    if str(msg.get("kind", "")) != KIND_AUDIO_CHUNK:
        return None, "BAD_KIND"
    room_id = _req_str(msg, "room_id")
    window_id = _req_str(msg, "window_id")
    utterance_id = _req_str(msg, "utterance_id")
    seat = _req_int(msg, "seat")
    hand_seq = _req_int(msg, "hand_seq")
    if room_id is None or window_id is None or utterance_id is None:
        return None, "INVALID_IDENTITY"
    if seat is None or seat < 0 or seat > 3:
        return None, "INVALID_SEAT"
    if hand_seq is None or hand_seq < 0:
        return None, "INVALID_HAND_SEQ"
    if not isinstance(msg.get("pcm_b64", None), str):
        return None, "INVALID_PCM_B64"
    want = msg.get("want_partial", False)
    if type(want) is not bool:
        return None, "INVALID_WANT_PARTIAL"
    return {
        "protocol_version": PROTOCOL_VERSION,
        "kind": KIND_AUDIO_CHUNK,
        "room_id": room_id,
        "seat": seat,
        "hand_seq": hand_seq,
        "window_id": window_id,
        "utterance_id": utterance_id,
        "pcm_b64": msg["pcm_b64"],
        "want_partial": want,
    }, None


def validate_commit(msg: Mapping[str, Any]) -> tuple[dict[str, Any] | None, str | None]:
    if _req_int(msg, "protocol_version") != PROTOCOL_VERSION:
        return None, "PROTOCOL_VERSION_UNSUPPORTED"
    if str(msg.get("kind", "")) != KIND_UTTERANCE_COMMIT:
        return None, "BAD_KIND"
    room_id = _req_str(msg, "room_id")
    window_id = _req_str(msg, "window_id")
    utterance_id = _req_str(msg, "utterance_id")
    seat = _req_int(msg, "seat")
    hand_seq = _req_int(msg, "hand_seq")
    ptt = _req_int(msg, "ptt_end_server_seq")
    if room_id is None or window_id is None or utterance_id is None:
        return None, "INVALID_IDENTITY"
    if seat is None or seat < 0 or seat > 3:
        return None, "INVALID_SEAT"
    if hand_seq is None or hand_seq < 0:
        return None, "INVALID_HAND_SEQ"
    if ptt is None or ptt <= 0:
        return None, "INVALID_PTT_END_SERVER_SEQ"
    return {
        "protocol_version": PROTOCOL_VERSION,
        "kind": KIND_UTTERANCE_COMMIT,
        "room_id": room_id,
        "seat": seat,
        "hand_seq": hand_seq,
        "window_id": window_id,
        "utterance_id": utterance_id,
        "ptt_end_server_seq": ptt,
    }, None


def validate_utt_cancel(msg: Mapping[str, Any]) -> tuple[dict[str, Any] | None, str | None]:
    if _req_int(msg, "protocol_version") != PROTOCOL_VERSION:
        return None, "PROTOCOL_VERSION_UNSUPPORTED"
    if str(msg.get("kind", "")) != KIND_UTTERANCE_CANCEL:
        return None, "BAD_KIND"
    room_id = _req_str(msg, "room_id")
    window_id = _req_str(msg, "window_id")
    utterance_id = _req_str(msg, "utterance_id")
    seat = _req_int(msg, "seat")
    hand_seq = _req_int(msg, "hand_seq")
    if room_id is None or window_id is None or utterance_id is None:
        return None, "INVALID_IDENTITY"
    if seat is None or seat < 0 or seat > 3:
        return None, "INVALID_SEAT"
    if hand_seq is None or hand_seq < 0:
        return None, "INVALID_HAND_SEQ"
    return {
        "protocol_version": PROTOCOL_VERSION,
        "kind": KIND_UTTERANCE_CANCEL,
        "room_id": room_id,
        "seat": seat,
        "hand_seq": hand_seq,
        "window_id": window_id,
        "utterance_id": utterance_id,
    }, None


def validate_window_cancel(msg: Mapping[str, Any]) -> tuple[dict[str, Any] | None, str | None]:
    if _req_int(msg, "protocol_version") != PROTOCOL_VERSION:
        return None, "PROTOCOL_VERSION_UNSUPPORTED"
    if str(msg.get("kind", "")) != KIND_WINDOW_CANCEL:
        return None, "BAD_KIND"
    room_id = _req_str(msg, "room_id")
    window_id = _req_str(msg, "window_id")
    hand_seq = _req_int(msg, "hand_seq")
    if room_id is None or window_id is None:
        return None, "INVALID_IDENTITY"
    if hand_seq is None or hand_seq < 0:
        return None, "INVALID_HAND_SEQ"
    return {
        "protocol_version": PROTOCOL_VERSION,
        "kind": KIND_WINDOW_CANCEL,
        "room_id": room_id,
        "hand_seq": hand_seq,
        "window_id": window_id,
    }, None


def make_partial(
    *,
    room_id: str,
    seat: int,
    hand_seq: int,
    window_id: str,
    utterance_id: str,
    ptt_end_server_seq: int | None,
    lang: str,
    text: str,
) -> dict[str, Any]:
    return {
        "protocol_version": PROTOCOL_VERSION,
        "kind": KIND_TRANSCRIPT_PARTIAL,
        "room_id": room_id,
        "seat": seat,
        "hand_seq": hand_seq,
        "window_id": window_id,
        "utterance_id": utterance_id,
        "ptt_end_server_seq": ptt_end_server_seq,
        "source": SOURCE,
        "lang": lang,
        "text": text,
        "is_final": False,
    }


def make_final(
    *,
    room_id: str,
    seat: int,
    hand_seq: int,
    window_id: str,
    utterance_id: str,
    ptt_end_server_seq: int,
    lang: str,
    text: str,
    duration_before_vad: float | None = None,
    duration_after_vad: float | None = None,
    wall_ms: int | None = None,
) -> dict[str, Any]:
    out: dict[str, Any] = {
        "protocol_version": PROTOCOL_VERSION,
        "kind": KIND_TRANSCRIPT_FINAL,
        "room_id": room_id,
        "seat": seat,
        "hand_seq": hand_seq,
        "window_id": window_id,
        "utterance_id": utterance_id,
        "ptt_end_server_seq": ptt_end_server_seq,
        "source": SOURCE,
        "lang": lang,
        "text": text,
        "is_final": True,
    }
    if duration_before_vad is not None:
        out["duration_before_vad"] = duration_before_vad
    if duration_after_vad is not None:
        out["duration_after_vad"] = duration_after_vad
    if wall_ms is not None:
        out["wall_ms"] = wall_ms
    return out


def make_failed(
    *,
    room_id: str,
    seat: int,
    hand_seq: int,
    window_id: str,
    utterance_id: str,
    ptt_end_server_seq: int | None,
    reason: str,
) -> dict[str, Any]:
    return {
        "protocol_version": PROTOCOL_VERSION,
        "kind": KIND_UTTERANCE_FAILED,
        "room_id": room_id,
        "seat": seat,
        "hand_seq": hand_seq,
        "window_id": window_id,
        "utterance_id": utterance_id,
        "ptt_end_server_seq": ptt_end_server_seq,
        "source": SOURCE,
        "reason": reason,
        "is_final": True,
        "text": "",
        "lang": "",
    }
