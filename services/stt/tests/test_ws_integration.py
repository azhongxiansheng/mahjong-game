from __future__ import annotations

import asyncio
import base64
import json
import time

import pytest
import websockets

from stt_service.config import SttConfig
from stt_service.server import SttServer
from stt_service.transcriber import TranscribeResult, WhisperTranscriber


class FakeTx(WhisperTranscriber):
    def __init__(self, cfg: SttConfig, sleep_s: float = 0.0):
        super().__init__(cfg)
        self.sleep_s = sleep_s

    def ensure_model(self):
        return object()

    def transcribe_pcm(self, pcm: bytes, *, is_final: bool) -> TranscribeResult:
        if self.sleep_s > 0:
            time.sleep(self.sleep_s)
        if not pcm or len(pcm) < 100:
            return TranscribeResult("", "", 0.0, 0.0, 1, "EMPTY")
        return TranscribeResult("hello world" if is_final else "hello", "en", 1.0, 0.9, 5, None)


async def _start(cfg, tx):
    srv = SttServer(config=cfg, transcriber=tx)
    from websockets.asyncio.server import serve

    async def handler(ws):
        await srv.handler(ws)

    server = await serve(handler, "127.0.0.1", 0)
    srv._server = server
    port = server.sockets[0].getsockname()[1]
    return srv, f"ws://127.0.0.1:{port}"


def _b64(n=400):
    return base64.b64encode(b"\x00\x10" * n).decode()


@pytest.mark.asyncio
async def test_ws_stream_and_commit():
    cfg = SttConfig(host="127.0.0.1", port=0, partial_interval_ms=0, max_pcm_bytes=2_000_000)
    srv, url = await _start(cfg, FakeTx(cfg))
    try:
        async with websockets.connect(url) as ws:
            await ws.send(json.dumps({
                "protocol_version": 1, "kind": "UTTERANCE_START",
                "room_id": "ra", "seat": 0, "hand_seq": 1, "window_id": "w1", "utterance_id": "u1",
            }))
            for _ in range(3):
                await ws.send(json.dumps({
                    "protocol_version": 1, "kind": "AUDIO_CHUNK",
                    "room_id": "ra", "seat": 0, "hand_seq": 1, "window_id": "w1", "utterance_id": "u1",
                    "pcm_b64": _b64(), "want_partial": True,
                }))
            await ws.send(json.dumps({
                "protocol_version": 1, "kind": "UTTERANCE_COMMIT",
                "room_id": "ra", "seat": 0, "hand_seq": 1, "window_id": "w1", "utterance_id": "u1",
                "ptt_end_server_seq": 42,
            }))
            final = None
            for _ in range(12):
                msg = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
                if msg.get("kind") == "TRANSCRIPT_FINAL":
                    final = msg
                    break
            assert final and final["ptt_end_server_seq"] == 42
    finally:
        srv._server.close()
        await srv._server.wait_closed()


@pytest.mark.asyncio
async def test_ws_window_cancel_with_hand_seq_and_preempt():
    cfg = SttConfig(host="127.0.0.1", port=0, max_pcm_bytes=2_000_000)
    srv, url = await _start(cfg, FakeTx(cfg, sleep_s=0.35))
    try:
        async with websockets.connect(url) as ws:
            await ws.send(json.dumps({
                "protocol_version": 1, "kind": "UTTERANCE_START",
                "room_id": "roomA", "seat": 0, "hand_seq": 0, "window_id": "same", "utterance_id": "uA",
            }))
            await ws.send(json.dumps({
                "protocol_version": 1, "kind": "AUDIO_CHUNK",
                "room_id": "roomA", "seat": 0, "hand_seq": 0, "window_id": "same", "utterance_id": "uA",
                "pcm_b64": _b64(),
            }))
            await ws.send(json.dumps({
                "protocol_version": 1, "kind": "UTTERANCE_COMMIT",
                "room_id": "roomA", "seat": 0, "hand_seq": 0, "window_id": "same", "utterance_id": "uA",
                "ptt_end_server_seq": 1,
            }))
            await asyncio.sleep(0.05)
            await ws.send(json.dumps({
                "protocol_version": 1, "kind": "WINDOW_CANCEL",
                "room_id": "roomA", "hand_seq": 0, "window_id": "same",
            }))
            saw = False
            for _ in range(20):
                msg = json.loads(await asyncio.wait_for(ws.recv(), timeout=3))
                if msg.get("kind") == "UTTERANCE_FAILED" and msg.get("reason") == "CANCELLED":
                    saw = True
                    assert msg["room_id"] == "roomA"
                    break
            assert saw
            # other hand same room+window name still ok
            await ws.send(json.dumps({
                "protocol_version": 1, "kind": "UTTERANCE_START",
                "room_id": "roomA", "seat": 1, "hand_seq": 1, "window_id": "same", "utterance_id": "uA2",
            }))
            await ws.send(json.dumps({
                "protocol_version": 1, "kind": "AUDIO_CHUNK",
                "room_id": "roomA", "seat": 1, "hand_seq": 1, "window_id": "same", "utterance_id": "uA2",
                "pcm_b64": _b64(),
            }))
            await ws.send(json.dumps({
                "protocol_version": 1, "kind": "UTTERANCE_COMMIT",
                "room_id": "roomA", "seat": 1, "hand_seq": 1, "window_id": "same", "utterance_id": "uA2",
                "ptt_end_server_seq": 2,
            }))
            got = None
            for _ in range(20):
                msg = json.loads(await asyncio.wait_for(ws.recv(), timeout=3))
                if msg.get("kind") == "TRANSCRIPT_FINAL" and msg.get("utterance_id") == "uA2":
                    got = msg
                    break
            assert got is not None
    finally:
        srv._server.close()
        await srv._server.wait_closed()


@pytest.mark.asyncio
async def test_ws_bad_types_do_not_kill_session():
    cfg = SttConfig(host="127.0.0.1", port=0, max_pcm_bytes=2_000_000)
    srv, url = await _start(cfg, FakeTx(cfg))
    try:
        async with websockets.connect(url) as ws:
            await ws.send(json.dumps({
                "protocol_version": 1, "kind": "UTTERANCE_START",
                "room_id": "r", "seat": 0, "hand_seq": 1.5, "window_id": "w", "utterance_id": "u",
            }))
            err = json.loads(await asyncio.wait_for(ws.recv(), timeout=3))
            assert err["kind"] == "ERROR"
            # connection still alive
            await ws.send(json.dumps({"protocol_version": 1, "kind": "PING"}))
            pong = json.loads(await asyncio.wait_for(ws.recv(), timeout=3))
            assert pong["kind"] == "PONG"
    finally:
        srv._server.close()
        await srv._server.wait_closed()


@pytest.mark.asyncio
async def test_ws_disconnect_releases():
    cfg = SttConfig(host="127.0.0.1", port=0, max_pcm_bytes=2_000_000)
    srv, url = await _start(cfg, FakeTx(cfg))
    try:
        async with websockets.connect(url) as ws:
            await ws.send(json.dumps({
                "protocol_version": 1, "kind": "UTTERANCE_START",
                "room_id": "r", "seat": 0, "hand_seq": 0, "window_id": "w", "utterance_id": "u",
            }))
            await ws.send(json.dumps({
                "protocol_version": 1, "kind": "AUDIO_CHUNK",
                "room_id": "r", "seat": 0, "hand_seq": 0, "window_id": "w", "utterance_id": "u",
                "pcm_b64": _b64(100),
            }))
            for _ in range(50):
                if srv.sessions.active_count() == 1:
                    break
                await asyncio.sleep(0.02)
            assert srv.sessions.active_count() == 1
        for _ in range(50):
            if srv.sessions.active_count() == 0:
                break
            await asyncio.sleep(0.02)
        assert srv.sessions.active_count() == 0
    finally:
        srv._server.close()
        await srv._server.wait_closed()


@pytest.mark.asyncio
async def test_ws_disconnect_during_slow_commit_slot_drains_after_thread():
    """慢推理中断开：会话/PCM 立即释放且不发送迟到结果；slot 等线程返回后才释放。"""
    # 全局上限=1：slot 占用时新 commit 必 TOO_MANY_INFER
    cfg = SttConfig(host="127.0.0.1", port=0, max_pcm_bytes=2_000_000, max_active_utterances=1)
    # SessionManager sets max_global_infer = max(4, max_active*2)=4 by default; force 1 via monkey
    srv, url = await _start(cfg, FakeTx(cfg, sleep_s=0.8))
    srv.sessions._max_global_infer = 1
    try:
        async with websockets.connect(url) as ws:
            await ws.send(json.dumps({
                "protocol_version": 1, "kind": "UTTERANCE_START",
                "room_id": "rd", "seat": 0, "hand_seq": 0, "window_id": "wd", "utterance_id": "ud",
            }))
            await ws.send(json.dumps({
                "protocol_version": 1, "kind": "AUDIO_CHUNK",
                "room_id": "rd", "seat": 0, "hand_seq": 0, "window_id": "wd", "utterance_id": "ud",
                "pcm_b64": _b64(),
            }))
            await ws.send(json.dumps({
                "protocol_version": 1, "kind": "UTTERANCE_COMMIT",
                "room_id": "rd", "seat": 0, "hand_seq": 0, "window_id": "wd", "utterance_id": "ud",
                "ptt_end_server_seq": 7,
            }))
            for _ in range(40):
                if srv.sessions._global_infer_inflight >= 1:
                    break
                await asyncio.sleep(0.02)
            assert srv.sessions._global_infer_inflight >= 1
        # 断连后：逻辑上 release_connection 会在 job 排空后执行；
        # 线程未返回前 inflight 仍占用（P1-4），active/PCM 在 cancel_token/finish 后清零。
        # 先在 short 窗口内观察：若 inflight 仍 >0，则新 commit 须 TOO_MANY_INFER
        held_seen = False
        for _ in range(30):
            if srv.sessions._global_infer_inflight >= 1:
                held_seen = True
                break
            await asyncio.sleep(0.02)
        if held_seen:
            async with websockets.connect(url) as ws_mid:
                await ws_mid.send(json.dumps({
                    "protocol_version": 1, "kind": "UTTERANCE_START",
                    "room_id": "rd", "seat": 0, "hand_seq": 0, "window_id": "wd", "utterance_id": "ud_mid",
                }))
                await ws_mid.send(json.dumps({
                    "protocol_version": 1, "kind": "AUDIO_CHUNK",
                    "room_id": "rd", "seat": 0, "hand_seq": 0, "window_id": "wd", "utterance_id": "ud_mid",
                    "pcm_b64": _b64(),
                }))
                await ws_mid.send(json.dumps({
                    "protocol_version": 1, "kind": "UTTERANCE_COMMIT",
                    "room_id": "rd", "seat": 0, "hand_seq": 0, "window_id": "wd", "utterance_id": "ud_mid",
                    "ptt_end_server_seq": 70,
                }))
                saw_over = False
                for _ in range(20):
                    try:
                        msg = json.loads(await asyncio.wait_for(ws_mid.recv(), timeout=0.5))
                    except asyncio.TimeoutError:
                        break
                    if msg.get("kind") == "UTTERANCE_FAILED" and msg.get("reason") == "TOO_MANY_INFER":
                        saw_over = True
                        break
                assert saw_over, "slow 未结束时新 commit 须受全局上限拒绝"
        # 等线程排空 slot 与 active
        for _ in range(100):
            if srv.sessions._global_infer_inflight == 0 and srv.sessions.active_count() == 0:
                break
            await asyncio.sleep(0.05)
        assert srv.sessions._global_infer_inflight == 0
        assert srv.sessions.active_count() == 0
        assert srv.sessions.total_pcm_bytes() == 0
        # 未来 utterance 成功
        async with websockets.connect(url) as ws2:
            await ws2.send(json.dumps({
                "protocol_version": 1, "kind": "UTTERANCE_START",
                "room_id": "rd", "seat": 0, "hand_seq": 0, "window_id": "wd", "utterance_id": "ud2",
            }))
            await ws2.send(json.dumps({
                "protocol_version": 1, "kind": "AUDIO_CHUNK",
                "room_id": "rd", "seat": 0, "hand_seq": 0, "window_id": "wd", "utterance_id": "ud2",
                "pcm_b64": _b64(),
            }))
            await ws2.send(json.dumps({
                "protocol_version": 1, "kind": "UTTERANCE_COMMIT",
                "room_id": "rd", "seat": 0, "hand_seq": 0, "window_id": "wd", "utterance_id": "ud2",
                "ptt_end_server_seq": 8,
            }))
            final = None
            for _ in range(30):
                msg = json.loads(await asyncio.wait_for(ws2.recv(), timeout=5))
                if msg.get("kind") == "TRANSCRIPT_FINAL" and msg.get("utterance_id") == "ud2":
                    final = msg
                    break
            assert final is not None
    finally:
        srv._server.close()
        await srv._server.wait_closed()


@pytest.mark.asyncio
@pytest.mark.slow
async def test_ws_real_model_en_fixture(fixtures_dir):
    path = fixtures_dir / "en_jfk_16k.wav"
    if not path.is_file():
        pytest.skip("missing fixture")
    from stt_service.transcriber import WhisperTranscriber

    cfg = SttConfig(host="127.0.0.1", port=0, model_size="small", device="cpu", compute_type="int8")
    tx = WhisperTranscriber(cfg)
    srv, url = await _start(cfg, tx)
    pcm = WhisperTranscriber.wav_bytes_to_pcm16(path.read_bytes())
    try:
        async with websockets.connect(url, max_size=8_000_000) as ws:
            await ws.send(json.dumps({
                "protocol_version": 1, "kind": "UTTERANCE_START",
                "room_id": "room_ws", "seat": 0, "hand_seq": 2, "window_id": "w_ws", "utterance_id": "utt_ws",
            }))
            frame = 640
            for i in range(0, len(pcm), frame):
                chunk = pcm[i : i + frame]
                if len(chunk) < frame:
                    chunk = chunk + b"\x00" * (frame - len(chunk))
                await ws.send(json.dumps({
                    "protocol_version": 1, "kind": "AUDIO_CHUNK",
                    "room_id": "room_ws", "seat": 0, "hand_seq": 2, "window_id": "w_ws", "utterance_id": "utt_ws",
                    "pcm_b64": base64.b64encode(chunk).decode(),
                }))
            await ws.send(json.dumps({
                "protocol_version": 1, "kind": "UTTERANCE_COMMIT",
                "room_id": "room_ws", "seat": 0, "hand_seq": 2, "window_id": "w_ws", "utterance_id": "utt_ws",
                "ptt_end_server_seq": 100,
            }))
            final = json.loads(await asyncio.wait_for(ws.recv(), timeout=120))
            assert final["kind"] == "TRANSCRIPT_FINAL"
            assert final["lang"] == "en"
            assert "ask" in final["text"].lower() or "country" in final["text"].lower()
    finally:
        srv._server.close()
        await srv._server.wait_closed()
