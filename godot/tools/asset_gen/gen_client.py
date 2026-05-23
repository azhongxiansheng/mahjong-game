"""gpt-image-2 client for 麻将王 asset generation.

Reads OpenAI-compatible gateway config from the environment, falling back to
parsing ~/.zshrc (the Bash tool's non-interactive shell does not source it).
Two gateways are tried in order so generation survives one being rate-limited.
"""
from __future__ import annotations

import base64
import os
import re
import time
from pathlib import Path

import requests

_ZSHRC = Path.home() / ".zshrc"


def _gateways() -> list[tuple[str, str]]:
    """Return [(base_url, api_key), ...] candidates, env first then ~/.zshrc."""
    out: list[tuple[str, str]] = []
    env_url = os.environ.get("OPENAI_BASE_URL", "").strip()
    env_key = os.environ.get("OPENAI_API_KEY", "").strip()
    if env_url and env_key:
        out.append((env_url, env_key))
    if _ZSHRC.exists():
        text = _ZSHRC.read_text(encoding="utf-8", errors="ignore")
        urls = re.findall(r'OPENAI_BASE_URL="([^"]+)"', text)
        keys = re.findall(r'OPENAI_API_KEY="([^"]+)"', text)
        # zshrc has two blocks; pair by appearance order.
        for url, key in zip(urls, keys):
            if (url, key) not in out:
                out.append((url, key))
    if not out:
        raise RuntimeError("no OpenAI gateway config found in env or ~/.zshrc")
    return out


def generate(prompt: str, size: str = "1024x1536", background: str = "transparent",
             quality: str = "high", n: int = 1) -> list[bytes]:
    """Generate image(s) via gpt-image-2; return list of PNG byte blobs."""
    last_err: Exception | None = None
    for base_url, api_key in _gateways():
        url = base_url.rstrip("/") + "/v1/images/generations"
        payload = {
            "model": "gpt-image-2",
            "prompt": prompt,
            "n": n,
            "size": size,
            "background": background,
            "quality": quality,
        }
        for attempt in range(3):
            try:
                resp = requests.post(
                    url,
                    headers={"Authorization": f"Bearer {api_key}",
                             "Content-Type": "application/json"},
                    json=payload,
                    timeout=300,
                )
                if resp.status_code != 200:
                    last_err = RuntimeError(
                        f"{base_url} HTTP {resp.status_code}: {resp.text[:300]}")
                    if resp.status_code in (429, 500, 502, 503, 504):
                        time.sleep(5 * (attempt + 1))
                        continue
                    break  # non-retryable on this gateway -> try next
                data = resp.json().get("data", [])
                blobs: list[bytes] = []
                for item in data:
                    b64 = item.get("b64_json")
                    if b64:
                        blobs.append(base64.b64decode(b64))
                    elif item.get("url"):
                        blobs.append(requests.get(item["url"], timeout=120).content)
                if blobs:
                    return blobs
                last_err = RuntimeError(f"{base_url}: empty data in response")
                break
            except requests.RequestException as e:
                last_err = e
                time.sleep(5 * (attempt + 1))
    raise RuntimeError(f"all gateways failed; last error: {last_err}")
