"""OpenAI-compatible /v1/audio/transcriptions backup client.

PCM16 LE mono 16 kHz is wrapped as in-memory WAV. Never writes audio or
transcripts to disk. Token must never appear in exceptions or logs.
"""

from __future__ import annotations

import io
import logging
import wave
from typing import Any

import httpx

from .config import SttConfig
from .protocol import SOURCE_NEW_API
from .transcriber import TranscribeResult

log = logging.getLogger("stt_service.new_api")


class NewApiError(Exception):
    """Stable, secret-free backup failure."""

    def __init__(self, reason: str) -> None:
        self.reason = reason
        super().__init__(reason)

    def __repr__(self) -> str:
        return f"NewApiError(reason={self.reason!r})"


def pcm16_to_wav_bytes(pcm: bytes, *, sample_rate: int = 16000, channels: int = 1) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(channels)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        wf.writeframes(pcm)
    return buf.getvalue()


def normalize_provider_lang(body: dict[str, Any]) -> str:
    """Prefer language_code; accept language string shapes; map to zh/en/ja."""
    raw = body.get("language_code")
    if raw is None or str(raw).strip() == "":
        raw = body.get("language")
    code = str(raw or "").strip().lower()
    mapping = {
        "zh": "zh",
        "chinese": "zh",
        "zh-cn": "zh",
        "zh-tw": "zh",
        "yue": "zh",
        "cmn": "zh",
        "en": "en",
        "english": "en",
        "ja": "ja",
        "japanese": "ja",
        "jp": "ja",
    }
    if code in mapping:
        return mapping[code]
    if len(code) >= 2 and code[:2] in mapping:
        return mapping[code[:2]]
    return code


class NewApiClient:
    def __init__(
        self,
        config: SttConfig,
        *,
        transport: httpx.AsyncBaseTransport | None = None,
        client: httpx.AsyncClient | None = None,
    ) -> None:
        self.config = config
        self._transport = transport
        self._client = client

    @property
    def enabled(self) -> bool:
        return self.config.new_api_enabled

    def _timeout(self) -> httpx.Timeout:
        sec = max(0.05, float(self.config.new_api_timeout_ms) / 1000.0)
        return httpx.Timeout(sec)

    async def transcribe_pcm(self, pcm: bytes) -> TranscribeResult:
        if not self.enabled:
            raise NewApiError("NEW_API_DISABLED")
        if not pcm:
            return TranscribeResult(
                text="",
                lang="",
                duration_before_vad=0.0,
                duration_after_vad=0.0,
                wall_ms=0,
                empty_reason="EMPTY",
                source=SOURCE_NEW_API,
            )

        wav = pcm16_to_wav_bytes(
            pcm,
            sample_rate=self.config.sample_rate,
            channels=self.config.channels,
        )
        headers = {"Authorization": f"Bearer {self.config.new_api_token}"}
        files = {"file": ("utterance.wav", wav, "audio/wav")}
        data = {
            "model": self.config.new_api_model,
            "response_format": "json",
        }
        owns_client = self._client is None
        # trust_env=False: avoid SOCKS/HTTP_PROXY hijacking internal backup calls.
        client = self._client or httpx.AsyncClient(
            timeout=self._timeout(),
            transport=self._transport,
            trust_env=False,
        )
        try:
            try:
                resp = await client.post(
                    self.config.new_api_endpoint,
                    headers=headers,
                    files=files,
                    data=data,
                )
            except httpx.TimeoutException:
                log.warning("new_api timeout")
                raise NewApiError("NEW_API_TIMEOUT") from None
            except httpx.HTTPError:
                log.warning("new_api transport error")
                raise NewApiError("NEW_API_TRANSPORT_ERROR") from None
        finally:
            if owns_client:
                await client.aclose()

        if resp.status_code < 200 or resp.status_code >= 300:
            log.warning("new_api http_status=%s", resp.status_code)
            raise NewApiError("NEW_API_HTTP_ERROR")

        try:
            body = resp.json()
        except Exception:
            raise NewApiError("NEW_API_INVALID_RESPONSE") from None
        if not isinstance(body, dict):
            raise NewApiError("NEW_API_INVALID_RESPONSE")

        text = str(body.get("text") or "").strip()
        lang = normalize_provider_lang(body)
        dur = float(body.get("duration") or 0.0)
        if not text:
            return TranscribeResult(
                text="",
                lang=lang if lang in self.config.allowed_langs else "",
                duration_before_vad=dur,
                duration_after_vad=dur,
                wall_ms=0,
                empty_reason="EMPTY",
                source=SOURCE_NEW_API,
            )
        if lang not in self.config.allowed_langs:
            return TranscribeResult(
                text="",
                lang=lang,
                duration_before_vad=dur,
                duration_after_vad=dur,
                wall_ms=0,
                empty_reason="LANG_FILTERED",
                source=SOURCE_NEW_API,
            )
        return TranscribeResult(
            text=text,
            lang=lang,
            duration_before_vad=dur,
            duration_after_vad=dur,
            wall_ms=0,
            empty_reason=None,
            source=SOURCE_NEW_API,
        )
