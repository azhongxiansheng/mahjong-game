"""Async WebSocket STT server — strict JSON, concurrent cancel-safe commit.

#248: primary faster-whisper with logical timeout; eligible final-only
new-api backup; circuit breaker; PONG health without secrets.
Network e2e not verified.
"""

from __future__ import annotations

import asyncio
import json
import logging
from typing import Any

from websockets.asyncio.server import ServerConnection, serve
from websockets.exceptions import ConnectionClosed

from .circuit_breaker import CircuitBreaker
from .config import SttConfig
from .new_api_client import NewApiClient, NewApiError
from .protocol import (
    KIND_AUDIO_CHUNK,
    KIND_ERROR,
    KIND_PING,
    KIND_PONG,
    KIND_UTTERANCE_CANCEL,
    KIND_UTTERANCE_COMMIT,
    KIND_UTTERANCE_START,
    KIND_WINDOW_CANCEL,
    PROTOCOL_VERSION,
    SOURCE_FASTER_WHISPER,
    SOURCE_NEW_API,
    validate_chunk,
    validate_commit,
    validate_start,
    validate_utt_cancel,
    validate_window_cancel,
)
from .session import SessionManager
from .transcriber import TranscribeResult, WhisperTranscriber

log = logging.getLogger("stt_service")



class SttServer:
    def __init__(
        self,
        config: SttConfig | None = None,
        transcriber: WhisperTranscriber | None = None,
        *,
        new_api_client: NewApiClient | None = None,
        circuit: CircuitBreaker | None = None,
    ) -> None:
        self.config = config or SttConfig.from_env()
        self.transcriber = transcriber or WhisperTranscriber(self.config)
        self.sessions = SessionManager(self.config, self.transcriber)
        self.new_api = new_api_client or NewApiClient(self.config)
        self.circuit = circuit or CircuitBreaker(
            failure_threshold=self.config.circuit_failure_threshold,
            cooldown_ms=self.config.circuit_cooldown_ms,
        )
        self._server = None
        self._next_conn_id = 1
        self._drain_tasks: set[asyncio.Task[Any]] = set()

    def health_summary(self) -> dict[str, Any]:
        """Backward-compatible PONG fields — no endpoint/model/token/raw errors."""
        enabled = bool(self.config.new_api_enabled)
        return {
            "primary": {"ok": True},
            "new_api": {
                "enabled": enabled,
                "circuit": self.circuit.state() if enabled else "DISABLED",
            },
        }

    async def handler(self, ws: ServerConnection) -> None:
        conn_id = self._next_conn_id
        self._next_conn_id += 1
        log.info("client connected conn=%s", conn_id)
        tasks: set[asyncio.Task[Any]] = set()
        try:
            async for raw in ws:
                if isinstance(raw, bytes):
                    await self._send(
                        ws,
                        {
                            "protocol_version": PROTOCOL_VERSION,
                            "kind": KIND_ERROR,
                            "code": "BINARY_UNSUPPORTED",
                        },
                    )
                    continue
                try:
                    await self._handle_text(ws, str(raw), conn_id, tasks)
                except Exception as e:  # isolate bad message
                    log.exception("handler error conn=%s: %s", conn_id, type(e).__name__)
                    await self._send(
                        ws,
                        {
                            "protocol_version": PROTOCOL_VERSION,
                            "kind": KIND_ERROR,
                            "code": "HANDLER_ERROR",
                        },
                    )
        except ConnectionClosed:
            pass
        finally:
            # 逻辑释放会话/PCM 立即；infer task 稍后排空 slot（P1-4）
            self.sessions.release_connection(conn_id)
            for t in list(tasks):
                t.cancel()
            if tasks:
                await asyncio.gather(*tasks, return_exceptions=True)
            log.info("client disconnected conn=%s", conn_id)

    async def _handle_text(
        self,
        ws: ServerConnection,
        raw: str,
        conn_id: int,
        tasks: set[asyncio.Task[Any]],
    ) -> None:
        try:
            msg = json.loads(raw)
        except json.JSONDecodeError:
            await self._send(ws, {"protocol_version": PROTOCOL_VERSION, "kind": KIND_ERROR, "code": "BAD_JSON"})
            return
        if not isinstance(msg, dict):
            await self._send(ws, {"protocol_version": PROTOCOL_VERSION, "kind": KIND_ERROR, "code": "BAD_JSON"})
            return
        kind = str(msg.get("kind", ""))
        if kind == KIND_PING:
            pong = {"protocol_version": PROTOCOL_VERSION, "kind": KIND_PONG}
            pong.update(self.health_summary())
            await self._send(ws, pong)
            return
        if kind == KIND_UTTERANCE_START:
            meta, err = validate_start(msg)
            if err or meta is None:
                await self._send(ws, {"protocol_version": PROTOCOL_VERSION, "kind": KIND_ERROR, "code": err or "BAD_START"})
                return
            _s, start_err = self.sessions.start(meta, conn_id=conn_id)
            if start_err:
                await self._send(
                    ws,
                    {
                        "protocol_version": PROTOCOL_VERSION,
                        "kind": KIND_ERROR,
                        "code": start_err,
                        "room_id": meta["room_id"],
                        "window_id": meta["window_id"],
                        "utterance_id": meta["utterance_id"],
                    },
                )
            return
        if kind == KIND_AUDIO_CHUNK:
            meta, err = validate_chunk(msg)
            if err or meta is None:
                await self._send(ws, {"protocol_version": PROTOCOL_VERSION, "kind": KIND_ERROR, "code": err or "BAD_CHUNK"})
                return
            aerr = self.sessions.append_b64(
                meta["room_id"],
                meta["seat"],
                meta["utterance_id"],
                meta["pcm_b64"],
                hand_seq=meta["hand_seq"],
                window_id=meta["window_id"],
                conn_id=conn_id,
            )
            if aerr == "OVERFLOW":
                await self._send(
                    ws,
                    {
                        "protocol_version": PROTOCOL_VERSION,
                        "kind": "UTTERANCE_FAILED",
                        "room_id": meta["room_id"],
                        "seat": meta["seat"],
                        "hand_seq": meta["hand_seq"],
                        "window_id": meta["window_id"],
                        "utterance_id": meta["utterance_id"],
                        "source": SOURCE_FASTER_WHISPER,
                        "reason": "OVERFLOW",
                        "is_final": True,
                        "text": "",
                        "lang": "",
                    },
                )
                return
            if aerr:
                await self._send(
                    ws,
                    {
                        "protocol_version": PROTOCOL_VERSION,
                        "kind": KIND_ERROR,
                        "code": aerr,
                        "room_id": meta["room_id"],
                        "utterance_id": meta["utterance_id"],
                    },
                )
                return
            if meta.get("want_partial"):
                async def _partial_job() -> None:
                    # Partial never calls new-api backup.
                    pcm, token, sess, perr = self.sessions.begin_partial(
                        meta["room_id"], meta["seat"], meta["utterance_id"]
                    )
                    if perr or pcm is None or sess is None:
                        return
                    loop = asyncio.get_running_loop()
                    fut = loop.run_in_executor(
                        None, lambda: self.transcriber.transcribe_pcm(pcm, is_final=False)
                    )
                    tr: Any = None
                    cancelled = False
                    try:
                        tr = await asyncio.shield(fut)
                    except asyncio.CancelledError:
                        cancelled = True
                        if fut.done():
                            try:
                                tr = fut.result()
                            except Exception:
                                tr = None
                        else:
                            try:
                                tr = await fut
                            except Exception:
                                tr = None
                    except Exception:
                        tr = None
                    out = self.sessions.end_partial(
                        meta["room_id"],
                        meta["seat"],
                        meta["utterance_id"],
                        token,
                        tr.text if tr else "",
                        tr.lang if tr else "",
                    )
                    if cancelled:
                        raise asyncio.CancelledError
                    if out is not None:
                        try:
                            await self._send(ws, out)
                        except ConnectionClosed:
                            pass

                t = asyncio.create_task(_partial_job())
                tasks.add(t)
                t.add_done_callback(lambda task: tasks.discard(task))
            return
        if kind == KIND_UTTERANCE_COMMIT:
            meta, err = validate_commit(msg)
            if err or meta is None:
                await self._send(ws, {"protocol_version": PROTOCOL_VERSION, "kind": KIND_ERROR, "code": err or "BAD_COMMIT"})
                return

            async def _commit_job() -> None:
                await self._run_commit(ws, meta, conn_id)

            t = asyncio.create_task(_commit_job())
            tasks.add(t)
            t.add_done_callback(lambda task: tasks.discard(task))
            return
        if kind == KIND_UTTERANCE_CANCEL:
            meta, err = validate_utt_cancel(msg)
            if err or meta is None:
                await self._send(ws, {"protocol_version": PROTOCOL_VERSION, "kind": KIND_ERROR, "code": err or "BAD_CANCEL"})
                return
            failed = self.sessions.cancel_utterance(
                meta["room_id"], meta["seat"], meta["hand_seq"], meta["window_id"], meta["utterance_id"]
            )
            if failed is not None:
                await self._send(ws, failed)
            return
        if kind == KIND_WINDOW_CANCEL:
            meta, err = validate_window_cancel(msg)
            if err or meta is None:
                await self._send(ws, {"protocol_version": PROTOCOL_VERSION, "kind": KIND_ERROR, "code": err or "BAD_WIN_CANCEL"})
                return
            for failed in self.sessions.cancel_window(meta["room_id"], meta["hand_seq"], meta["window_id"]):
                await self._send(ws, failed)
            return
        await self._send(ws, {"protocol_version": PROTOCOL_VERSION, "kind": KIND_ERROR, "code": "UNKNOWN_KIND"})

    async def _run_commit(
        self,
        ws: ServerConnection,
        meta: dict[str, Any],
        conn_id: int,
    ) -> None:
        # P1-4：逻辑 cancel 可立即释放会话/PCM；infer slot 等 executor 线程返回后再 finish。
        pcm, token, sess, early = self.sessions.begin_commit(meta, conn_id)
        if early is not None:
            try:
                await self._send(ws, early)
            except ConnectionClosed:
                pass
            return
        if pcm is None and sess is None and early is None:
            return  # idempotent ignore in-flight same ptt
        if pcm is None or sess is None:
            return
        if not pcm:
            out = self.sessions.finish_commit(meta, token, None)
            try:
                await self._send(ws, out)
            except ConnectionClosed:
                pass
            return

        loop = asyncio.get_running_loop()
        fut = loop.run_in_executor(
            None, lambda: self.transcriber.transcribe_pcm(pcm, is_final=True)
        )
        tr: TranscribeResult | None = None
        cancelled = False
        timed_out = False
        primary_error = False
        timeout_s = max(0.05, float(self.config.primary_timeout_ms) / 1000.0)

        try:
            tr = await asyncio.wait_for(asyncio.shield(fut), timeout=timeout_s)
        except asyncio.TimeoutError:
            timed_out = True
            tr = None
        except asyncio.CancelledError:
            cancelled = True
            if fut.done():
                try:
                    tr = fut.result()
                except Exception:
                    tr = None
            else:
                try:
                    tr = await fut
                except Exception:
                    tr = None
        except Exception:
            primary_error = True
            tr = None

        if cancelled:
            out = self.sessions.finish_commit(meta, token, tr)
            raise asyncio.CancelledError

        # Eligible fallback: primary exception or logical timeout only.
        # Normal empty terminals are NOT supplier failures.
        eligible = timed_out or primary_error
        release_slot = True

        if eligible:
            fb = await self._run_new_api_fallback(pcm)
            if fb is not None:
                tr = fb
            elif timed_out:
                tr = TranscribeResult(
                    "", "", 0.0, 0.0, 0, empty_reason="PRIMARY_TIMEOUT", source=SOURCE_FASTER_WHISPER
                )
            else:
                tr = TranscribeResult(
                    "", "", 0.0, 0.0, 0, empty_reason="PRIMARY_ERROR", source=SOURCE_FASTER_WHISPER
                )
            if timed_out and not fut.done():
                release_slot = False

        out = self.sessions.finish_commit(meta, token, tr, release_slot=release_slot)

        if timed_out and not fut.done():
            self._schedule_primary_drain(fut)
        elif timed_out and fut.done() and not release_slot:
            # Primary finished during fallback; release held slot once.
            self.sessions.abort_infer_slot()

        try:
            await self._send(ws, out)
        except ConnectionClosed:
            pass

    def _schedule_primary_drain(self, fut: asyncio.Future[Any]) -> None:
        async def _drain() -> None:
            try:
                await fut
            except Exception:
                pass
            finally:
                # Late primary: release slot only — never re-finish / re-broadcast.
                self.sessions.abort_infer_slot()

        t = asyncio.create_task(_drain())
        self._drain_tasks.add(t)
        t.add_done_callback(lambda task: self._drain_tasks.discard(task))

    async def _run_new_api_fallback(self, pcm: bytes) -> TranscribeResult | None:
        """Attempt backup. None means disabled (caller keeps PRIMARY_* reason)."""
        if not self.config.new_api_enabled:
            return None
        permit = self.circuit.try_acquire()
        if permit is None:
            return TranscribeResult(
                "",
                "",
                0.0,
                0.0,
                0,
                empty_reason="NEW_API_CIRCUIT_OPEN",
                source=SOURCE_NEW_API,
            )
        try:
            result = await self.new_api.transcribe_pcm(pcm)
            # 2xx with parseable body (incl. empty text) is not a circuit failure.
            self.circuit.record_success(permit)
            return result
        except NewApiError as e:
            self.circuit.record_failure(permit)
            return TranscribeResult(
                "",
                "",
                0.0,
                0.0,
                0,
                empty_reason=e.reason,
                source=SOURCE_NEW_API,
            )
        except Exception:
            self.circuit.record_failure(permit)
            log.warning("new_api unexpected error type")
            return TranscribeResult(
                "",
                "",
                0.0,
                0.0,
                0,
                empty_reason="NEW_API_TRANSPORT_ERROR",
                source=SOURCE_NEW_API,
            )

    async def _send(self, ws: ServerConnection, msg: dict[str, Any]) -> None:
        await ws.send(json.dumps(msg, ensure_ascii=False, separators=(",", ":")))

    async def run(self) -> None:
        await asyncio.to_thread(self.transcriber.ensure_model)
        async with serve(self.handler, self.config.host, self.config.port) as server:
            self._server = server
            log.info(
                "stt listening ws://%s:%d new_api_enabled=%s (network e2e not verified)",
                self.config.host,
                self.config.port,
                self.config.new_api_enabled,
            )
            await server.serve_forever()


async def run_server(config: SttConfig | None = None) -> None:
    await SttServer(config=config).run()
