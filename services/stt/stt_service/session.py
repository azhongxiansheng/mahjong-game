"""Thread-safe utterance sessions: OPEN → COMMITTING → TERMINAL/CANCELLED.

gen_key = room_id|hand_seq|window_id
"""

from __future__ import annotations

import base64
import threading
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any

from .config import SttConfig
from .protocol import make_failed, make_final, make_partial
from .transcriber import WhisperTranscriber


class Phase(str, Enum):
    OPEN = "OPEN"
    COMMITTING = "COMMITTING"
    TERMINAL = "TERMINAL"
    CANCELLED = "CANCELLED"


def gen_key(room_id: str, hand_seq: int, window_id: str) -> str:
    return f"{room_id}|{hand_seq}|{window_id}"


def utt_key(room_id: str, seat: int, utterance_id: str) -> str:
    return f"{room_id}|{seat}|{utterance_id}"


@dataclass
class UtteranceSession:
    room_id: str
    seat: int
    hand_seq: int
    window_id: str
    utterance_id: str
    conn_id: int = 0
    pcm: bytearray = field(default_factory=bytearray)
    ptt_end_server_seq: int | None = None
    phase: Phase = Phase.OPEN
    cancel_token: int = 0
    partial_running: bool = False
    last_partial_ms: int = 0
    final_result: dict[str, Any] | None = None

    def gkey(self) -> str:
        return gen_key(self.room_id, self.hand_seq, self.window_id)

    def key(self) -> str:
        return utt_key(self.room_id, self.seat, self.utterance_id)


class SessionManager:
    def __init__(self, config: SttConfig, transcriber: WhisperTranscriber) -> None:
        self.config = config
        self.transcriber = transcriber
        self._lock = threading.RLock()
        self._active: dict[str, UtteranceSession] = {}
        self._cancelled_gens: dict[str, bool] = {}  # ordered-ish via _cancel_order
        self._cancel_order: list[str] = []
        self._max_cancel_tombstones = 128
        self._conn_utts: dict[int, set[str]] = {}
        self._global_infer_inflight = 0
        self._max_global_infer = max(4, config.max_active_utterances * 2)
        # 短命终态缓存：同 identity+ptt 重复 commit 幂等
        self._final_cache: dict[str, dict[str, Any]] = {}
        self._final_order: list[str] = []
        self._max_final_cache = 64

    def clear_all(self) -> None:
        with self._lock:
            self._active.clear()
            self._cancelled_gens.clear()
            self._cancel_order.clear()
            self._conn_utts.clear()
            self._global_infer_inflight = 0
            self._final_cache.clear()
            self._final_order.clear()

    def active_count(self) -> int:
        with self._lock:
            return len(self._active)

    def total_pcm_bytes(self) -> int:
        with self._lock:
            return sum(len(s.pcm) for s in self._active.values())

    def release_connection(self, conn_id: int) -> None:
        with self._lock:
            keys = list(self._conn_utts.pop(conn_id, set()))
            for k in keys:
                self._release_unlocked(k)

    def is_gen_cancelled(self, room_id: str, hand_seq: int, window_id: str) -> bool:
        with self._lock:
            return gen_key(room_id, hand_seq, window_id) in self._cancelled_gens

    def _add_cancel_tombstone(self, gk: str) -> None:
        if gk not in self._cancelled_gens:
            self._cancel_order.append(gk)
        self._cancelled_gens[gk] = True
        while len(self._cancel_order) > self._max_cancel_tombstones:
            old = self._cancel_order.pop(0)
            self._cancelled_gens.pop(old, None)

    def cancel_window(self, room_id: str, hand_seq: int, window_id: str) -> list[dict[str, Any]]:
        with self._lock:
            gk = gen_key(room_id, hand_seq, window_id)
            self._add_cancel_tombstone(gk)
            out: list[dict[str, Any]] = []
            dead: list[str] = []
            for k, s in self._active.items():
                if s.room_id == room_id and s.hand_seq == hand_seq and s.window_id == window_id:
                    s.phase = Phase.CANCELLED
                    s.cancel_token += 1
                    out.append(
                        make_failed(
                            room_id=s.room_id,
                            seat=s.seat,
                            hand_seq=s.hand_seq,
                            window_id=s.window_id,
                            utterance_id=s.utterance_id,
                            ptt_end_server_seq=s.ptt_end_server_seq,
                            reason="CANCELLED",
                        )
                    )
                    dead.append(k)
            for k in dead:
                self._release_unlocked(k)
            return out

    def cancel_utterance(
        self, room_id: str, seat: int, hand_seq: int, window_id: str, utterance_id: str
    ) -> dict[str, Any] | None:
        with self._lock:
            key = utt_key(room_id, seat, utterance_id)
            s = self._active.get(key)
            if s is None:
                return None
            if s.hand_seq != hand_seq or s.window_id != window_id or s.room_id != room_id:
                return None
            s.phase = Phase.CANCELLED
            s.cancel_token += 1
            msg = make_failed(
                room_id=s.room_id,
                seat=s.seat,
                hand_seq=s.hand_seq,
                window_id=s.window_id,
                utterance_id=s.utterance_id,
                ptt_end_server_seq=s.ptt_end_server_seq,
                reason="CANCELLED",
            )
            self._release_unlocked(key)
            return msg

    def start(self, meta: dict[str, Any], conn_id: int = 0) -> tuple[UtteranceSession | None, str | None]:
        with self._lock:
            gk = gen_key(meta["room_id"], int(meta["hand_seq"]), meta["window_id"])
            if gk in self._cancelled_gens:
                return None, "WINDOW_CANCELLED"
            if len(self._active) >= self.config.max_active_utterances:
                return None, "TOO_MANY_UTTERANCES"
            key = utt_key(meta["room_id"], int(meta["seat"]), meta["utterance_id"])
            if key in self._active:
                s = self._active[key]
                if s.conn_id == conn_id and s.phase == Phase.OPEN:
                    return s, None
                return None, "UTTERANCE_ALREADY_OPEN"
            s = UtteranceSession(
                room_id=meta["room_id"],
                seat=int(meta["seat"]),
                hand_seq=int(meta["hand_seq"]),
                window_id=meta["window_id"],
                utterance_id=meta["utterance_id"],
                conn_id=conn_id,
            )
            self._active[key] = s
            self._conn_utts.setdefault(conn_id, set()).add(key)
            return s, None

    def append_b64(
        self,
        room_id: str,
        seat: int,
        utterance_id: str,
        b64: str,
        *,
        hand_seq: int,
        window_id: str,
        conn_id: int | None = None,
    ) -> str | None:
        try:
            pcm = base64.b64decode(b64, validate=True)
        except Exception:
            return "BAD_BASE64"
        with self._lock:
            key = utt_key(room_id, seat, utterance_id)
            s = self._active.get(key)
            if s is None:
                return "NO_UTTERANCE"
            if conn_id is not None and s.conn_id != conn_id:
                return "CONN_MISMATCH"
            if s.window_id != window_id or s.hand_seq != hand_seq or s.room_id != room_id:
                return "CONTEXT_MISMATCH"
            if s.phase != Phase.OPEN:
                return "NOT_OPEN"
            if gen_key(s.room_id, s.hand_seq, s.window_id) in self._cancelled_gens:
                self._release_unlocked(key)
                return "CANCELLED"
            if not pcm:
                return "EMPTY_CHUNK"
            if len(s.pcm) + len(pcm) > self.config.max_pcm_bytes:
                self._release_unlocked(key)
                return "OVERFLOW"
            max_by_ms = int(self.config.sample_rate * 2 * (self.config.max_utterance_ms / 1000.0))
            if len(s.pcm) + len(pcm) > max_by_ms:
                self._release_unlocked(key)
                return "OVERFLOW"
            s.pcm.extend(pcm)
            return None

    def begin_partial(
        self, room_id: str, seat: int, utterance_id: str
    ) -> tuple[bytes | None, int, UtteranceSession | None, str | None]:
        """Return (pcm_copy, cancel_token, session_snapshot, error)."""
        with self._lock:
            if self._global_infer_inflight >= self._max_global_infer:
                return None, 0, None, "TOO_MANY_INFER"
            key = utt_key(room_id, seat, utterance_id)
            s = self._active.get(key)
            if s is None:
                return None, 0, None, "NO_UTTERANCE"
            if s.phase != Phase.OPEN or s.partial_running:
                return None, 0, None, "BUSY"
            if gen_key(s.room_id, s.hand_seq, s.window_id) in self._cancelled_gens:
                return None, 0, None, "CANCELLED"
            now = int(time.time() * 1000)
            if s.last_partial_ms and now - s.last_partial_ms < self.config.partial_interval_ms:
                return None, 0, None, "THROTTLED"
            if len(s.pcm) < self.config.bytes_per_frame * 10:
                return None, 0, None, "TOO_SHORT"
            s.partial_running = True
            s.last_partial_ms = now
            self._global_infer_inflight += 1
            return bytes(s.pcm), s.cancel_token, s, None

    def end_partial(
        self,
        room_id: str,
        seat: int,
        utterance_id: str,
        token: int,
        result_text: str,
        result_lang: str,
    ) -> dict[str, Any] | None:
        with self._lock:
            self._global_infer_inflight = max(0, self._global_infer_inflight - 1)
            key = utt_key(room_id, seat, utterance_id)
            s = self._active.get(key)
            if s is None:
                return None
            s.partial_running = False
            # No partial after commit/terminal/cancel
            if s.phase != Phase.OPEN or s.cancel_token != token:
                return None
            if gen_key(s.room_id, s.hand_seq, s.window_id) in self._cancelled_gens:
                return None
            if not result_text:
                return None
            return make_partial(
                room_id=s.room_id,
                seat=s.seat,
                hand_seq=s.hand_seq,
                window_id=s.window_id,
                utterance_id=s.utterance_id,
                ptt_end_server_seq=s.ptt_end_server_seq,
                lang=result_lang or "",
                text=result_text,
            )

    def begin_commit(
        self, meta: dict[str, Any], conn_id: int | None = None
    ) -> tuple[bytes | None, int, UtteranceSession | None, dict[str, Any] | None]:
        """Returns (pcm, token, session, early_response)."""
        with self._lock:
            key = utt_key(meta["room_id"], int(meta["seat"]), meta["utterance_id"])
            fkey = f"{key}|{int(meta['ptt_end_server_seq'])}"
            # 先查终态缓存，避免重复 commit 复活已释放的 active
            if fkey in self._final_cache:
                return None, 0, None, self._final_cache[fkey]
            s = self._active.get(key)
            if s is None:
                if gen_key(meta["room_id"], int(meta["hand_seq"]), meta["window_id"]) in self._cancelled_gens:
                    return None, 0, None, make_failed(
                        room_id=meta["room_id"],
                        seat=int(meta["seat"]),
                        hand_seq=int(meta["hand_seq"]),
                        window_id=meta["window_id"],
                        utterance_id=meta["utterance_id"],
                        ptt_end_server_seq=int(meta["ptt_end_server_seq"]),
                        reason="CANCELLED",
                    )
                s = UtteranceSession(
                    room_id=meta["room_id"],
                    seat=int(meta["seat"]),
                    hand_seq=int(meta["hand_seq"]),
                    window_id=meta["window_id"],
                    utterance_id=meta["utterance_id"],
                    conn_id=conn_id or 0,
                )
                self._active[key] = s
                if conn_id is not None:
                    self._conn_utts.setdefault(conn_id, set()).add(key)
            if s.phase == Phase.TERMINAL and s.final_result is not None:
                return None, 0, None, s.final_result  # idempotent
            if s.phase == Phase.COMMITTING:
                # 同 ptt 重复 commit：忽略，不破坏首次；不同 ptt 稳定拒绝
                if s.ptt_end_server_seq == int(meta["ptt_end_server_seq"]):
                    return None, 0, None, None  # caller skips send
                return None, 0, None, make_failed(
                    room_id=s.room_id,
                    seat=s.seat,
                    hand_seq=s.hand_seq,
                    window_id=s.window_id,
                    utterance_id=s.utterance_id,
                    ptt_end_server_seq=int(meta["ptt_end_server_seq"]),
                    reason="PTT_CONFLICT",
                )
            if s.phase in (Phase.CANCELLED, Phase.TERMINAL):
                return None, 0, None, make_failed(
                    room_id=s.room_id,
                    seat=s.seat,
                    hand_seq=s.hand_seq,
                    window_id=s.window_id,
                    utterance_id=s.utterance_id,
                    ptt_end_server_seq=int(meta["ptt_end_server_seq"]),
                    reason="ALREADY_TERMINAL",
                )
            if (
                s.window_id != meta["window_id"]
                or s.room_id != meta["room_id"]
                or s.seat != int(meta["seat"])
                or s.hand_seq != int(meta["hand_seq"])
            ):
                self._release_unlocked(key)
                return None, 0, None, make_failed(
                    room_id=meta["room_id"],
                    seat=int(meta["seat"]),
                    hand_seq=int(meta["hand_seq"]),
                    window_id=meta["window_id"],
                    utterance_id=meta["utterance_id"],
                    ptt_end_server_seq=int(meta["ptt_end_server_seq"]),
                    reason="CONTEXT_MISMATCH",
                )
            if gen_key(s.room_id, s.hand_seq, s.window_id) in self._cancelled_gens:
                self._release_unlocked(key)
                return None, 0, None, make_failed(
                    room_id=s.room_id,
                    seat=s.seat,
                    hand_seq=s.hand_seq,
                    window_id=s.window_id,
                    utterance_id=s.utterance_id,
                    ptt_end_server_seq=int(meta["ptt_end_server_seq"]),
                    reason="CANCELLED",
                )
            if self._global_infer_inflight >= self._max_global_infer:
                # P1-3：overload 是该 commit 终态失败，必须释放 active/PCM，避免堆积
                out = make_failed(
                    room_id=s.room_id,
                    seat=s.seat,
                    hand_seq=s.hand_seq,
                    window_id=s.window_id,
                    utterance_id=s.utterance_id,
                    ptt_end_server_seq=int(meta["ptt_end_server_seq"]),
                    reason="TOO_MANY_INFER",
                )
                fkey_ov = f"{key}|{int(meta['ptt_end_server_seq'])}"
                self._final_cache[fkey_ov] = out
                self._final_order.append(fkey_ov)
                while len(self._final_order) > self._max_final_cache:
                    old = self._final_order.pop(0)
                    self._final_cache.pop(old, None)
                self._release_unlocked(key)
                return None, 0, None, out
            s.ptt_end_server_seq = int(meta["ptt_end_server_seq"])
            s.phase = Phase.COMMITTING
            s.cancel_token += 1  # invalidate in-flight partials
            token = s.cancel_token
            pcm = bytes(s.pcm)
            s.pcm = bytearray()
            self._global_infer_inflight += 1
            return pcm, token, s, None

    def finish_commit(
        self,
        meta: dict[str, Any],
        token: int,
        result: Any,
    ) -> dict[str, Any]:
        with self._lock:
            self._global_infer_inflight = max(0, self._global_infer_inflight - 1)
            key = utt_key(meta["room_id"], int(meta["seat"]), meta["utterance_id"])
            s = self._active.get(key)
            if s is None:
                return make_failed(
                    room_id=meta["room_id"],
                    seat=int(meta["seat"]),
                    hand_seq=int(meta["hand_seq"]),
                    window_id=meta["window_id"],
                    utterance_id=meta["utterance_id"],
                    ptt_end_server_seq=int(meta["ptt_end_server_seq"]),
                    reason="CANCELLED",
                )
            if s.phase == Phase.CANCELLED or s.cancel_token != token:
                self._release_unlocked(key)
                return make_failed(
                    room_id=s.room_id,
                    seat=s.seat,
                    hand_seq=s.hand_seq,
                    window_id=s.window_id,
                    utterance_id=s.utterance_id,
                    ptt_end_server_seq=s.ptt_end_server_seq,
                    reason="CANCELLED",
                )
            if gen_key(s.room_id, s.hand_seq, s.window_id) in self._cancelled_gens:
                self._release_unlocked(key)
                return make_failed(
                    room_id=s.room_id,
                    seat=s.seat,
                    hand_seq=s.hand_seq,
                    window_id=s.window_id,
                    utterance_id=s.utterance_id,
                    ptt_end_server_seq=s.ptt_end_server_seq,
                    reason="CANCELLED",
                )
            if result is None or getattr(result, "empty_reason", None) or not getattr(result, "text", "").strip():
                out = make_failed(
                    room_id=s.room_id,
                    seat=s.seat,
                    hand_seq=s.hand_seq,
                    window_id=s.window_id,
                    utterance_id=s.utterance_id,
                    ptt_end_server_seq=s.ptt_end_server_seq,
                    reason=getattr(result, "empty_reason", None) or "EMPTY",
                )
            else:
                out = make_final(
                    room_id=s.room_id,
                    seat=s.seat,
                    hand_seq=s.hand_seq,
                    window_id=s.window_id,
                    utterance_id=s.utterance_id,
                    ptt_end_server_seq=int(s.ptt_end_server_seq or meta["ptt_end_server_seq"]),
                    lang=result.lang,
                    text=result.text,
                    duration_before_vad=result.duration_before_vad,
                    duration_after_vad=result.duration_after_vad,
                    wall_ms=result.wall_ms,
                )
            s.phase = Phase.TERMINAL
            s.final_result = out
            fkey = f"{key}|{int(s.ptt_end_server_seq or meta['ptt_end_server_seq'])}"
            self._final_cache[fkey] = out
            self._final_order.append(fkey)
            while len(self._final_order) > self._max_final_cache:
                old = self._final_order.pop(0)
                self._final_cache.pop(old, None)
            self._release_unlocked(key)
            return out

    def abort_infer_slot(self) -> None:
        """Ensure begin_* inflight is released after cancel/exception (exactly once per begin)."""
        with self._lock:
            self._global_infer_inflight = max(0, self._global_infer_inflight - 1)

    def force_partial_idle(self, room_id: str, seat: int, utterance_id: str) -> None:
        with self._lock:
            s = self._active.get(utt_key(room_id, seat, utterance_id))
            if s is not None:
                s.partial_running = False

    def force_commit_abort(self, meta: dict[str, Any], token: int) -> dict[str, Any]:
        """Release COMMITTING after cancelled/exception without emitting success."""
        with self._lock:
            self._global_infer_inflight = max(0, self._global_infer_inflight - 1)
            key = utt_key(meta["room_id"], int(meta["seat"]), meta["utterance_id"])
            s = self._active.get(key)
            if s is not None and s.cancel_token == token:
                s.phase = Phase.CANCELLED
                self._release_unlocked(key)
            return make_failed(
                room_id=meta["room_id"],
                seat=int(meta["seat"]),
                hand_seq=int(meta["hand_seq"]),
                window_id=meta["window_id"],
                utterance_id=meta["utterance_id"],
                ptt_end_server_seq=int(meta["ptt_end_server_seq"]),
                reason="CANCELLED",
            )

    def _release_unlocked(self, key: str) -> None:
        s = self._active.pop(key, None)
        if s is None:
            return
        s.pcm = bytearray()
        owned = self._conn_utts.get(s.conn_id)
        if owned is not None:
            owned.discard(key)
            if not owned:
                self._conn_utts.pop(s.conn_id, None)
