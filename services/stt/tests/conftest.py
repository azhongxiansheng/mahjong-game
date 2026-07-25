from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

# Prefer local HF cache; avoid SOCKS proxy breaking offline loads in CI/dev shells.
os.environ.setdefault("HF_HUB_OFFLINE", "1")
for _k in ("ALL_PROXY", "all_proxy", "HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy"):
    os.environ.pop(_k, None)

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

FIXTURES = ROOT / "fixtures"


@pytest.fixture(scope="session")
def fixtures_dir() -> Path:
    return FIXTURES


@pytest.fixture(scope="session")
def stt_config():
    from stt_service.config import SttConfig

    # Force CPU int8 small; never hard-code user home cache.
    return SttConfig(
        host="127.0.0.1",
        port=0,
        model_size=os.environ.get("STT_MODEL", "small"),
        device=os.environ.get("STT_DEVICE", "cpu"),
        compute_type=os.environ.get("STT_COMPUTE_TYPE", "int8"),
        model_cache_dir=os.environ.get("STT_MODEL_CACHE", ""),
        partial_interval_ms=0,
    )


@pytest.fixture(scope="session")
def transcriber(stt_config):
    from stt_service.transcriber import WhisperTranscriber

    t = WhisperTranscriber(stt_config)
    t.ensure_model()
    return t


def load_pcm(path: Path) -> bytes:
    from stt_service.transcriber import WhisperTranscriber

    return WhisperTranscriber.wav_bytes_to_pcm16(path.read_bytes())
