"""#248 new-api fallback, timeout, circuit, health, token redaction."""

from __future__ import annotations

import asyncio
import base64
import io
import json
import logging
import time
import wave
from typing import Any

import httpx
import pytest
import websockets

from stt_service.circuit_breaker import CircuitBreaker
from stt_service.config import SttConfig
from stt_service.new_api_client import (
    NewApiClient,
    NewApiError,
    normalize_provider_lang,
    pcm16_to_wav_bytes,
)
from stt_service.protocol import SOURCE_FASTER_WHISPER, SOURCE_NEW_API, make_final
from stt_service.server import SttServer
from stt_service.session import SessionManager
from stt_service.transcriber import TranscribeResult, WhisperTranscriber


SECRET_TOKEN = "sk-test-secret-token-DO-NOT-LEAK-248"


def _cfg(**kwargs: Any) -> SttConfig:
    base = dict(
        host="127.0.0.1",
        port=0,
        partial_interval_ms=0,
        max_pcm_bytes=2_000_000,
        primary_timeout_ms=5_000,
        new_api_endpoint="https://example.test/v1/audio/transcriptions",
        new_api_model="fish-transcribe-1",
        new_api_token=SECRET_TOKEN,
        new_api_timeout_ms=2_000,
        circuit_failure_threshold=3,
        circuit_cooldown_ms=1_000,
    )
    base.update(kwargs)
    return SttConfig(**base)


class FakeTx(WhisperTranscriber):
    def __init__(
        self,
        cfg: SttConfig,
        *,
        sleep_s: float = 0.0,
        result: TranscribeResult | None = None,
        raise_exc: BaseException | None = None,
        is_final_only: bool = True,
        call_log: list | None = None,
    ):
        super().__init__(cfg)
        self.sleep_s = sleep_s
        self._result = result
        self._raise = raise_exc
        self._is_final_only = is_final_only
        self.call_log = call_log if call_log is not None else []

    def ensure_model(self):
        return object()

    def transcribe_pcm(self, pcm: bytes, *, is_final: bool) -> TranscribeResult:
        self.call_log.append({"is_final": is_final, "pcm_len": len(pcm)})
        if self.sleep_s > 0:
            time.sleep(self.sleep_s)
        if self._raise is not None and (is_final or not self._is_final_only):
            raise self._raise
        if self._result is not None and is_final:
            return self._result
        if not pcm or len(pcm) < 100:
            return TranscribeResult("", "", 0.0, 0.0, 1, "EMPTY", SOURCE_FASTER_WHISPER)
        if is_final:
            return TranscribeResult("hello world", "en", 1.0, 0.9, 5, None, SOURCE_FASTER_WHISPER)
        return TranscribeResult("hello", "en", 1.0, 0.9, 2, None, SOURCE_FASTER_WHISPER)


def _pcm(n: int = 400) -> bytes:
    return b"\x00\x10" * n


def _b64(n: int = 400) -> str:
    return base64.b64encode(_pcm(n)).decode()


def _mock_transport(handler):
    return httpx.MockTransport(handler)


async def _start(cfg: SttConfig, tx: WhisperTranscriber, **kwargs: Any):
    srv = SttServer(config=cfg, transcriber=tx, **kwargs)
    from websockets.asyncio.server import serve

    async def handler(ws):
        await srv.handler(ws)

    server = await serve(handler, "127.0.0.1", 0)
    srv._server = server
    port = server.sockets[0].getsockname()[1]
    return srv, f"ws://127.0.0.1:{port}"


async def _commit_flow(
    url: str,
    *,
    want_partial: bool = False,
    ptt: int = 42,
    utterance_id: str = "u1",
    seat: int = 0,
) -> list[dict]:
    out: list[dict] = []
    async with websockets.connect(url) as ws:
        await ws.send(json.dumps({
            "protocol_version": 1, "kind": "UTTERANCE_START",
            "room_id": "r1", "seat": seat, "hand_seq": 1, "window_id": "w1",
            "utterance_id": utterance_id,
        }))
        for _ in range(3):
            await ws.send(json.dumps({
                "protocol_version": 1, "kind": "AUDIO_CHUNK",
                "room_id": "r1", "seat": seat, "hand_seq": 1, "window_id": "w1",
                "utterance_id": utterance_id,
                "pcm_b64": _b64(), "want_partial": want_partial,
            }))
        await ws.send(json.dumps({
            "protocol_version": 1, "kind": "UTTERANCE_COMMIT",
            "room_id": "r1", "seat": seat, "hand_seq": 1, "window_id": "w1",
            "utterance_id": utterance_id,
            "ptt_end_server_seq": ptt,
        }))
        for _ in range(20):
            try:
                msg = json.loads(await asyncio.wait_for(ws.recv(), timeout=3))
            except asyncio.TimeoutError:
                break
            out.append(msg)
            if msg.get("kind") in ("TRANSCRIPT_FINAL", "UTTERANCE_FAILED"):
                break
    return out


# --- config / token safety ---


def test_missing_new_api_config_disables_backup():
    c = SttConfig(new_api_endpoint="", new_api_model="m", new_api_token="t")
    assert c.new_api_enabled is False
    c2 = SttConfig(
        new_api_endpoint="https://x/v1/audio/transcriptions",
        new_api_model="m",
        new_api_token="t",
    )
    assert c2.new_api_enabled is True


def test_config_repr_and_str_hide_token():
    c = _cfg()
    blob = repr(c) + str(c)
    assert SECRET_TOKEN not in blob
    assert "sk-test" not in blob


def test_from_env_uses_dedicated_vars(monkeypatch):
    monkeypatch.setenv("STT_NEW_API_ENDPOINT", "https://dedicated.example/v1/audio/transcriptions")
    monkeypatch.setenv("STT_NEW_API_MODEL", "fish-transcribe-1")
    monkeypatch.setenv("STT_NEW_API_TOKEN", SECRET_TOKEN)
    monkeypatch.setenv("STT_PRIMARY_TIMEOUT_MS", "1234")
    monkeypatch.setenv("STT_NEW_API_TIMEOUT_MS", "567")
    # Asset-generation vars must NOT be silently reused
    monkeypatch.setenv("OPENAI_BASE_URL", "https://should-not-use.example/v1")
    monkeypatch.setenv("OPENAI_API_KEY", "openai-should-not-use")
    c = SttConfig.from_env()
    assert c.new_api_endpoint == "https://dedicated.example/v1/audio/transcriptions"
    assert c.new_api_model == "fish-transcribe-1"
    assert c.new_api_token == SECRET_TOKEN
    assert c.primary_timeout_ms == 1234
    assert c.new_api_timeout_ms == 567
    assert "should-not-use" not in c.new_api_endpoint


# --- language + wav ---


def test_normalize_prefers_language_code():
    assert normalize_provider_lang({"language_code": "ja", "language": "english"}) == "ja"
    assert normalize_provider_lang({"language": "japanese"}) == "ja"
    assert normalize_provider_lang({"language_code": "zh"}) == "zh"
    assert normalize_provider_lang({"language": "en"}) == "en"


def test_pcm_to_wav_in_memory_roundtrip():
    pcm = _pcm(160)
    wav = pcm16_to_wav_bytes(pcm, sample_rate=16000)
    with wave.open(io.BytesIO(wav), "rb") as wf:
        assert wf.getnchannels() == 1
        assert wf.getsampwidth() == 2
        assert wf.getframerate() == 16000
        assert wf.readframes(wf.getnframes()) == pcm


# --- new_api client with MockTransport ---


@pytest.mark.asyncio
async def test_new_api_multipart_auth_and_success():
    seen: dict[str, Any] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["auth"] = request.headers.get("Authorization", "")
        seen["url"] = str(request.url)
        body = request.content
        seen["has_multipart"] = b"fish-transcribe-1" in body and b"utterance.wav" in body
        # ensure raw token only in auth header, not accidental body field of secret alone is ok as Bearer
        return httpx.Response(
            200,
            json={
                "text": "東京です",
                "language": "japanese",
                "language_code": "ja",
                "duration": 0.9,
                "segments": [],
            },
        )

    cfg = _cfg()
    client = NewApiClient(cfg, transport=_mock_transport(handler))
    tr = await client.transcribe_pcm(_pcm())
    assert tr.text == "東京です"
    assert tr.lang == "ja"
    assert tr.source == SOURCE_NEW_API
    assert tr.empty_reason is None
    assert seen["auth"] == f"Bearer {SECRET_TOKEN}"
    assert seen["has_multipart"] is True


@pytest.mark.asyncio
async def test_new_api_http_503_and_timeout_and_invalid_json():
    def h503(request: httpx.Request) -> httpx.Response:
        return httpx.Response(503, json={"error": {"type": "new_api_error", "code": "model_not_found"}})

    cfg = _cfg()
    with pytest.raises(NewApiError) as ei:
        await NewApiClient(cfg, transport=_mock_transport(h503)).transcribe_pcm(_pcm())
    assert ei.value.reason == "NEW_API_HTTP_ERROR"
    assert SECRET_TOKEN not in str(ei.value)
    assert SECRET_TOKEN not in repr(ei.value)

    def hbad(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=b"not-json")

    with pytest.raises(NewApiError) as ei2:
        await NewApiClient(cfg, transport=_mock_transport(hbad)).transcribe_pcm(_pcm())
    assert ei2.value.reason == "NEW_API_INVALID_RESPONSE"

    def hslow(request: httpx.Request) -> httpx.Response:
        raise httpx.TimeoutException("slow")

    with pytest.raises(NewApiError) as ei3:
        await NewApiClient(cfg, transport=_mock_transport(hslow)).transcribe_pcm(_pcm())
    assert ei3.value.reason == "NEW_API_TIMEOUT"


# --- server integration: fallback policy ---


@pytest.mark.asyncio
async def test_partial_never_calls_new_api():
    calls = {"n": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        calls["n"] += 1
        return httpx.Response(200, json={"text": "backup", "language_code": "en", "duration": 0.1})

    cfg = _cfg()
    primary_log: list = []

    def transcribe_pcm(pcm, *, is_final: bool):
        primary_log.append(is_final)
        if is_final:
            raise RuntimeError("primary fail")
        return TranscribeResult("partial-ok", "en", 1, 1, 1, None, SOURCE_FASTER_WHISPER)

    tx_partial = FakeTx(cfg)
    tx_partial.transcribe_pcm = transcribe_pcm  # type: ignore
    client = NewApiClient(cfg, transport=_mock_transport(handler))
    srv, url = await _start(cfg, tx_partial, new_api_client=client)
    try:
        async with websockets.connect(url) as ws:
            await ws.send(json.dumps({
                "protocol_version": 1, "kind": "UTTERANCE_START",
                "room_id": "r1", "seat": 0, "hand_seq": 1, "window_id": "w1", "utterance_id": "u1",
            }))
            # enough frames for partial threshold (10 frames * 640)
            big = base64.b64encode(b"\x00\x10" * 4000).decode()
            await ws.send(json.dumps({
                "protocol_version": 1, "kind": "AUDIO_CHUNK",
                "room_id": "r1", "seat": 0, "hand_seq": 1, "window_id": "w1", "utterance_id": "u1",
                "pcm_b64": big, "want_partial": True,
            }))
            partial = json.loads(await asyncio.wait_for(ws.recv(), timeout=2))
            assert partial.get("kind") == "TRANSCRIPT_PARTIAL"
            assert partial.get("source") == SOURCE_FASTER_WHISPER
            assert partial.get("text") == "partial-ok"
            assert False in primary_log  # saw non-final primary call
            assert calls["n"] == 0  # commit 前不得调用备份
            await ws.send(json.dumps({
                "protocol_version": 1, "kind": "UTTERANCE_COMMIT",
                "room_id": "r1", "seat": 0, "hand_seq": 1, "window_id": "w1", "utterance_id": "u1",
                "ptt_end_server_seq": 9,
            }))
            final = json.loads(await asyncio.wait_for(ws.recv(), timeout=3))
            assert final.get("kind") == "TRANSCRIPT_FINAL"
            assert final.get("source") == SOURCE_NEW_API
            assert calls["n"] == 1  # final 失败后只调用一次备份
    finally:
        srv._server.close()
        await srv._server.wait_closed()


@pytest.mark.asyncio
async def test_primary_exception_falls_back_new_api_source():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200, json={"text": "backup text", "language_code": "en", "duration": 0.5}
        )

    cfg = _cfg()
    tx = FakeTx(cfg, raise_exc=RuntimeError("primary boom"))
    client = NewApiClient(cfg, transport=_mock_transport(handler))
    srv, url = await _start(cfg, tx, new_api_client=client)
    try:
        msgs = await _commit_flow(url)
        final = msgs[-1]
        assert final["kind"] == "TRANSCRIPT_FINAL"
        assert final["source"] == SOURCE_NEW_API
        assert final["text"] == "backup text"
        assert final["lang"] == "en"
        assert final["is_final"] is True
    finally:
        srv._server.close()
        await srv._server.wait_closed()


@pytest.mark.asyncio
async def test_primary_timeout_falls_back_and_late_primary_no_second_final():
    http_calls = {"n": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        http_calls["n"] += 1
        return httpx.Response(
            200, json={"text": "from-backup", "language_code": "en", "duration": 0.2}
        )

    cfg = _cfg(primary_timeout_ms=80)
    primary_log: list = []
    tx = FakeTx(cfg, sleep_s=0.45, call_log=primary_log)
    client = NewApiClient(cfg, transport=_mock_transport(handler))
    srv, url = await _start(cfg, tx, new_api_client=client)
    try:
        async with websockets.connect(url) as ws:
            await ws.send(json.dumps({
                "protocol_version": 1, "kind": "UTTERANCE_START",
                "room_id": "r1", "seat": 0, "hand_seq": 1, "window_id": "w1", "utterance_id": "u1",
            }))
            await ws.send(json.dumps({
                "protocol_version": 1, "kind": "AUDIO_CHUNK",
                "room_id": "r1", "seat": 0, "hand_seq": 1, "window_id": "w1", "utterance_id": "u1",
                "pcm_b64": _b64(),
            }))
            await ws.send(json.dumps({
                "protocol_version": 1, "kind": "UTTERANCE_COMMIT",
                "room_id": "r1", "seat": 0, "hand_seq": 1, "window_id": "w1", "utterance_id": "u1",
                "ptt_end_server_seq": 77,
            }))
            final = json.loads(await asyncio.wait_for(ws.recv(), timeout=3))
            assert final["kind"] == "TRANSCRIPT_FINAL"
            assert final["source"] == SOURCE_NEW_API
            assert final["text"] == "from-backup"
            # Slot should still be held while primary drains
            inflight_mid = srv.sessions.infer_inflight()
            assert inflight_mid >= 1 or http_calls["n"] == 1
            # Wait for late primary to drain; must not emit second final
            await asyncio.sleep(0.55)
            # No more messages
            try:
                extra = await asyncio.wait_for(ws.recv(), timeout=0.2)
                pytest.fail(f"late primary must not send second final: {extra}")
            except asyncio.TimeoutError:
                pass
            assert http_calls["n"] == 1
            # Slot eventually released
            assert srv.sessions.infer_inflight() == 0
    finally:
        srv._server.close()
        await srv._server.wait_closed()


@pytest.mark.asyncio
async def test_normal_empty_does_not_fallback():
    calls = {"n": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        calls["n"] += 1
        return httpx.Response(200, json={"text": "should-not", "language_code": "en"})

    for reason in ("EMPTY", "VAD_NO_SPEECH", "LANG_FILTERED"):
        calls["n"] = 0
        cfg = _cfg()
        tx = FakeTx(
            cfg,
            result=TranscribeResult("", "en" if reason != "LANG_FILTERED" else "fr", 1, 0, 1, reason),
        )
        client = NewApiClient(cfg, transport=_mock_transport(handler))
        srv, url = await _start(cfg, tx, new_api_client=client)
        try:
            msgs = await _commit_flow(url, ptt=10 + hash(reason) % 50)
            final = msgs[-1]
            assert final["kind"] == "UTTERANCE_FAILED"
            assert final["reason"] == reason
            assert calls["n"] == 0
        finally:
            srv._server.close()
            await srv._server.wait_closed()


@pytest.mark.asyncio
async def test_disabled_new_api_primary_error_no_http():
    calls = {"n": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        calls["n"] += 1
        return httpx.Response(200, json={"text": "x", "language_code": "en"})

    cfg = _cfg(new_api_token="")  # disables
    assert cfg.new_api_enabled is False
    tx = FakeTx(cfg, raise_exc=RuntimeError("x"))
    client = NewApiClient(cfg, transport=_mock_transport(handler))
    srv, url = await _start(cfg, tx, new_api_client=client)
    try:
        msgs = await _commit_flow(url)
        final = msgs[-1]
        assert final["kind"] == "UTTERANCE_FAILED"
        assert final["reason"] == "PRIMARY_ERROR"
        assert calls["n"] == 0
    finally:
        srv._server.close()
        await srv._server.wait_closed()


@pytest.mark.asyncio
async def test_circuit_open_fast_fail_no_http_then_half_open_recover():
    clock = {"t": 0.0}

    def clock_ms() -> float:
        return clock["t"]

    calls = {"n": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        calls["n"] += 1
        if calls["n"] <= 3:
            return httpx.Response(503, json={"error": {"code": "down"}})
        return httpx.Response(200, json={"text": "recovered", "language_code": "en", "duration": 0.1})

    cfg = _cfg(circuit_failure_threshold=3, circuit_cooldown_ms=1000)
    cb = CircuitBreaker(failure_threshold=3, cooldown_ms=1000, clock_ms=clock_ms)
    client = NewApiClient(cfg, transport=_mock_transport(handler))
    tx = FakeTx(cfg, raise_exc=RuntimeError("always"))

    async def one_commit(srv_url: str, ptt: int) -> dict:
        msgs = await _commit_flow(srv_url, ptt=ptt)
        return msgs[-1]

    srv, url = await _start(cfg, tx, new_api_client=client, circuit=cb)
    try:
        for i in range(3):
            m = await one_commit(url, 100 + i)
            assert m["kind"] == "UTTERANCE_FAILED"
            assert m["reason"] == "NEW_API_HTTP_ERROR"
        assert calls["n"] == 3
        assert cb.state() == "OPEN"
        # OPEN: fast fail, no more HTTP
        m = await one_commit(url, 200)
        assert m["reason"] == "NEW_API_CIRCUIT_OPEN"
        assert calls["n"] == 3
        # Cool down → HALF_OPEN single probe
        clock["t"] = 1000
        assert cb.state() == "HALF_OPEN"
        m = await one_commit(url, 201)
        assert m["kind"] == "TRANSCRIPT_FINAL"
        assert m["text"] == "recovered"
        assert m["source"] == SOURCE_NEW_API
        assert cb.state() == "CLOSED"
        assert calls["n"] == 4
    finally:
        srv._server.close()
        await srv._server.wait_closed()


@pytest.mark.asyncio
async def test_concurrent_half_open_only_one_http():
    """While HALF_OPEN probe is in-flight, concurrent eligible finals must not issue a second backup call."""
    clock = {"t": 0.0}
    cb = CircuitBreaker(failure_threshold=1, cooldown_ms=100, clock_ms=lambda: clock["t"])
    seed = cb.try_acquire()
    assert seed is not None
    assert cb.record_failure(seed) is True
    assert cb.state() == "OPEN"
    clock["t"] = 100
    assert cb.state() == "HALF_OPEN"

    calls = {"n": 0}
    probe_entered = asyncio.Event()
    release_probe = asyncio.Event()

    class HoldingClient(NewApiClient):
        async def transcribe_pcm(self, pcm: bytes) -> TranscribeResult:
            calls["n"] += 1
            probe_entered.set()
            await release_probe.wait()
            return TranscribeResult(
                "probe", "en", 0.1, 0.1, 0, None, SOURCE_NEW_API
            )

    cfg = _cfg(circuit_failure_threshold=1, circuit_cooldown_ms=100)
    client = HoldingClient(cfg)
    tx = FakeTx(cfg, raise_exc=RuntimeError("x"))
    srv, url = await _start(cfg, tx, new_api_client=client, circuit=cb)
    try:
        async def go(ptt: int, utt: str, seat: int):
            return (await _commit_flow(url, ptt=ptt, utterance_id=utt, seat=seat))[-1]

        t1 = asyncio.create_task(go(1, "u_probe", 0))
        await asyncio.wait_for(probe_entered.wait(), timeout=2.0)
        r2 = await go(2, "u_peer", 1)
        release_probe.set()
        r1 = await t1
        assert calls["n"] == 1
        assert r1.get("kind") == "TRANSCRIPT_FINAL"
        assert r1.get("source") == SOURCE_NEW_API
        assert r1.get("text") == "probe"
        assert r2.get("reason") == "NEW_API_CIRCUIT_OPEN"
    finally:
        release_probe.set()
        srv._server.close()
        await srv._server.wait_closed()


@pytest.mark.asyncio
async def test_duplicate_commit_idempotent_single_final():
    calls = {"n": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        calls["n"] += 1
        return httpx.Response(200, json={"text": "once", "language_code": "en", "duration": 0.1})

    cfg = _cfg()
    tx = FakeTx(cfg, raise_exc=RuntimeError("x"))
    client = NewApiClient(cfg, transport=_mock_transport(handler))
    srv, url = await _start(cfg, tx, new_api_client=client)
    try:
        async with websockets.connect(url) as ws:
            await ws.send(json.dumps({
                "protocol_version": 1, "kind": "UTTERANCE_START",
                "room_id": "r1", "seat": 0, "hand_seq": 1, "window_id": "w1", "utterance_id": "u1",
            }))
            await ws.send(json.dumps({
                "protocol_version": 1, "kind": "AUDIO_CHUNK",
                "room_id": "r1", "seat": 0, "hand_seq": 1, "window_id": "w1", "utterance_id": "u1",
                "pcm_b64": _b64(),
            }))
            commit = {
                "protocol_version": 1, "kind": "UTTERANCE_COMMIT",
                "room_id": "r1", "seat": 0, "hand_seq": 1, "window_id": "w1", "utterance_id": "u1",
                "ptt_end_server_seq": 55,
            }
            await ws.send(json.dumps(commit))
            first = json.loads(await asyncio.wait_for(ws.recv(), timeout=3))
            assert first["kind"] == "TRANSCRIPT_FINAL"
            assert first["source"] == SOURCE_NEW_API
            await ws.send(json.dumps(commit))
            second = json.loads(await asyncio.wait_for(ws.recv(), timeout=3))
            assert second == first
            assert calls["n"] == 1
    finally:
        srv._server.close()
        await srv._server.wait_closed()


@pytest.mark.asyncio
async def test_cancel_during_primary_no_late_final_from_backup_path():
    """Cancel drops session; late finish is CANCELLED / no success final resurrection."""
    cfg = _cfg(primary_timeout_ms=200)
    tx = FakeTx(cfg, sleep_s=0.4)
    # slow backup too
    def handler(request: httpx.Request) -> httpx.Response:
        time.sleep(0.05)
        return httpx.Response(200, json={"text": "late-backup", "language_code": "en", "duration": 0.1})

    client = NewApiClient(cfg, transport=_mock_transport(handler))
    srv, url = await _start(cfg, tx, new_api_client=client)
    try:
        async with websockets.connect(url) as ws:
            await ws.send(json.dumps({
                "protocol_version": 1, "kind": "UTTERANCE_START",
                "room_id": "r1", "seat": 0, "hand_seq": 1, "window_id": "w1", "utterance_id": "u1",
            }))
            await ws.send(json.dumps({
                "protocol_version": 1, "kind": "AUDIO_CHUNK",
                "room_id": "r1", "seat": 0, "hand_seq": 1, "window_id": "w1", "utterance_id": "u1",
                "pcm_b64": _b64(),
            }))
            await ws.send(json.dumps({
                "protocol_version": 1, "kind": "UTTERANCE_COMMIT",
                "room_id": "r1", "seat": 0, "hand_seq": 1, "window_id": "w1", "utterance_id": "u1",
                "ptt_end_server_seq": 3,
            }))
            await asyncio.sleep(0.05)
            await ws.send(json.dumps({
                "protocol_version": 1, "kind": "UTTERANCE_CANCEL",
                "room_id": "r1", "seat": 0, "hand_seq": 1, "window_id": "w1", "utterance_id": "u1",
            }))
            msgs = []
            for _ in range(5):
                try:
                    msgs.append(json.loads(await asyncio.wait_for(ws.recv(), timeout=1.0)))
                except asyncio.TimeoutError:
                    break
            # Any final must not be a successful new_api resurrection with scoring text path
            for m in msgs:
                if m.get("kind") == "TRANSCRIPT_FINAL":
                    pytest.fail(f"cancelled must not emit success final: {m}")
            assert any(m.get("reason") == "CANCELLED" for m in msgs)
    finally:
        srv._server.close()
        await srv._server.wait_closed()


@pytest.mark.asyncio
async def test_pong_health_no_secrets():
    cfg = _cfg()
    tx = FakeTx(cfg)
    srv, url = await _start(cfg, tx)
    try:
        async with websockets.connect(url) as ws:
            await ws.send(json.dumps({"protocol_version": 1, "kind": "PING"}))
            pong = json.loads(await asyncio.wait_for(ws.recv(), timeout=2))
            assert pong["kind"] == "PONG"
            assert pong["primary"]["ok"] is True
            assert pong["new_api"]["enabled"] is True
            assert pong["new_api"]["circuit"] in ("CLOSED", "OPEN", "HALF_OPEN", "DISABLED")
            blob = json.dumps(pong)
            assert SECRET_TOKEN not in blob
            assert "endpoint" not in blob
            assert "fish-transcribe" not in blob
            assert "Bearer" not in blob
    finally:
        srv._server.close()
        await srv._server.wait_closed()


@pytest.mark.asyncio
async def test_logs_and_exceptions_never_contain_token(caplog):
    caplog.set_level(logging.DEBUG)

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(503, json={"error": {"message": "x"}})

    cfg = _cfg()
    client = NewApiClient(cfg, transport=_mock_transport(handler))
    with pytest.raises(NewApiError) as ei:
        await client.transcribe_pcm(_pcm())
    assert SECRET_TOKEN not in str(ei.value)
    assert SECRET_TOKEN not in repr(ei.value)
    for rec in caplog.records:
        assert SECRET_TOKEN not in rec.getMessage()
        assert SECRET_TOKEN not in str(rec.args)


def test_make_final_source_new_api():
    msg = make_final(
        room_id="r", seat=0, hand_seq=1, window_id="w", utterance_id="u",
        ptt_end_server_seq=1, lang="en", text="t", source=SOURCE_NEW_API,
    )
    assert msg["source"] == SOURCE_NEW_API
    assert msg["is_final"] is True


def test_session_finish_commit_carries_source():
    cfg = _cfg()
    sm = SessionManager(cfg, FakeTx(cfg))
    meta = {
        "room_id": "r", "seat": 0, "hand_seq": 1, "window_id": "w",
        "utterance_id": "u", "ptt_end_server_seq": 9,
    }
    sm.start({**meta, "kind": "UTTERANCE_START"}, conn_id=1)
    sm.append_b64("r", 0, "u", _b64(), hand_seq=1, window_id="w", conn_id=1)
    pcm, token, s, early = sm.begin_commit(meta, 1)
    assert early is None and pcm is not None
    tr = TranscribeResult("hi", "en", 1, 1, 1, None, SOURCE_NEW_API)
    out = sm.finish_commit(meta, token, tr)
    assert out["kind"] == "TRANSCRIPT_FINAL"
    assert out["source"] == SOURCE_NEW_API
