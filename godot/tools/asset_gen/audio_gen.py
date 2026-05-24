"""tts-1 client for 麻将王 voice line generation.

Reuses the same OpenAI-compatible gateway config as gen_client.py (env first,
then ~/.zshrc). Calls /v1/audio/speech with model=tts-1, voice=<onyx/nova/...>
to produce mp3 voice lines for Japanese mahjong announcements (リーチ / ツモ /
ロン / チー / ポン / カン / 流局 等).
"""
from __future__ import annotations

import os
import re
import time
from pathlib import Path

import requests

_ZSHRC = Path.home() / ".zshrc"


def _gateways() -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []
    env_url = os.environ.get("OPENAI_BASE_URL", "").strip()
    env_key = os.environ.get("OPENAI_API_KEY", "").strip()
    if env_url and env_key:
        out.append((env_url, env_key))
    if _ZSHRC.exists():
        text = _ZSHRC.read_text(encoding="utf-8", errors="ignore")
        urls = re.findall(r'OPENAI_BASE_URL="([^"]+)"', text)
        keys = re.findall(r'OPENAI_API_KEY="([^"]+)"', text)
        for url, key in zip(urls, keys):
            if (url, key) not in out:
                out.append((url, key))
    if not out:
        raise RuntimeError("no OpenAI gateway config found in env or ~/.zshrc")
    return out


# OpenAI tts-1 voice catalog (alloy/echo/fable/onyx/nova/shimmer)。
# 选 4 个性别+音色差异最大的给 4 个 seat 配音差异化。
VOICE_BY_SEAT: dict[int, str] = {
    0: "onyx",     # player — 沉稳男声
    1: "nova",     # 下家 — 年轻女声
    2: "echo",     # 对家 — 平和男声
    3: "shimmer",  # 上家 — 温柔女声
}


def synthesize(text: str, voice: str = "onyx", speed: float = 1.0,
               response_format: str = "mp3") -> bytes:
    """Synthesize voice from text via tts-1; return audio bytes."""
    last_err: Exception | None = None
    for base_url, api_key in _gateways():
        url = base_url.rstrip("/") + "/v1/audio/speech"
        payload = {
            "model": "tts-1",
            "input": text,
            "voice": voice,
            "speed": speed,
            "response_format": response_format,
        }
        for attempt in range(3):
            try:
                resp = requests.post(
                    url,
                    headers={"Authorization": f"Bearer {api_key}",
                             "Content-Type": "application/json"},
                    json=payload,
                    timeout=120,
                )
                if resp.status_code != 200:
                    last_err = RuntimeError(
                        f"{base_url} HTTP {resp.status_code}: {resp.text[:300]}")
                    if resp.status_code in (429, 500, 502, 503, 504):
                        time.sleep(3 * (attempt + 1))
                        continue
                    break
                # response is the raw audio bytes (mp3 / opus / etc)
                return resp.content
            except requests.RequestException as e:
                last_err = e
                time.sleep(3 * (attempt + 1))
    raise RuntimeError(f"all gateways failed; last error: {last_err}")
