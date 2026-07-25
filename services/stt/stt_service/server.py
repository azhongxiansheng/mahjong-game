"""Async WebSocket STT server — strict JSON, concurrent cancel-safe commit."""

from __future__ import annotations

import asyncio
import json
import logging
from typing import Any

from websockets.asyncio.server import ServerConnection, serve
from websockets.exceptions import ConnectionClosed

from .config import SttConfig
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
    validate_chunk,
    validate_commit,
    validate_start,
    validate_utt_cancel,
    validate_window_cancel,
)
from .session import SessionManager
from .transcriber import WhisperTranscriber

log = logging.getLogger("stt_service")


class SttServer:
    def __init__(
        self,
        config: SttConfig | None = None,
        transcriber: WhisperTranscriber | None = None,
    ) -> None:
        self.config = config or SttConfig.from_env()
        self.transcriber = transcriber or WhisperTranscriber(self.config)
        self.sessions = SessionManager(self.config, self.transcriber)
        self._server = None
        self._next_conn_id = 1

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
                    log.exception("handler error conn=%s: %s", conn_id, e)
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
            await self._send(ws, {"protocol_version": PROTOCOL_VERSION, "kind": KIND_PONG})
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
                        "source": "faster_whisper",
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
                    # P1-4：slot 仅在底层线程返回后由 end_partial 释放
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
                # P1-4：逻辑 cancel 可立即释放会话/PCM；infer slot 等 executor 线程返回后再 finish。
                # shield 推迟 CancelledError 至底层 Future 完成，避免提前减 slot。
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
                        # 极少见：再等完成
                        try:
                            tr = await fut
                        except Exception:
                            tr = None
                except Exception:
                    tr = None
                out = self.sessions.finish_commit(meta, token, tr)
                if cancelled:
                    raise asyncio.CancelledError
                try:
                    await self._send(ws, out)
                except ConnectionClosed:
                    pass

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

    async def _send(self, ws: ServerConnection, msg: dict[str, Any]) -> None:
        await ws.send(json.dumps(msg, ensure_ascii=False, separators=(",", ":")))

    async def run(self) -> None:
        await asyncio.to_thread(self.transcriber.ensure_model)
        async with serve(self.handler, self.config.host, self.config.port) as server:
            self._server = server
            log.info(
                "stt listening ws://%s:%d (network e2e not verified)",
                self.config.host,
                self.config.port,
            )
            await server.serve_forever()


async def run_server(config: SttConfig | None = None) -> None:
    await SttServer(config=config).run()
