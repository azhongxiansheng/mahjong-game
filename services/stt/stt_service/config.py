"""Runtime config via credential-free environment variables only."""

from __future__ import annotations

import os
from dataclasses import dataclass


def _env(name: str, default: str) -> str:
    v = os.environ.get(name)
    if v is None or str(v).strip() == "":
        return default
    return str(v).strip()


def _env_int(name: str, default: int) -> int:
    raw = _env(name, str(default))
    try:
        return int(raw)
    except ValueError:
        return default


def _env_float(name: str, default: float) -> float:
    raw = _env(name, str(default))
    try:
        return float(raw)
    except ValueError:
        return default


@dataclass(frozen=True)
class SttConfig:
    host: str = "127.0.0.1"
    port: int = 9100
    model_size: str = "small"
    device: str = "cpu"
    compute_type: str = "int8"
    # Optional HF / model cache dir; empty => library default (no hard-coded user path).
    model_cache_dir: str = ""
    sample_rate: int = 16000
    channels: int = 1
    frame_ms: int = 20
    bytes_per_frame: int = 640  # 16k * 2 * 0.02
    # Hard caps — deterministic fail + free memory.
    max_utterance_ms: int = 30_000
    max_pcm_bytes: int = 16000 * 2 * 30  # 960_000
    max_active_utterances: int = 16
    partial_interval_ms: int = 800
    # Whisper decode knobs (CPU-friendly defaults).
    beam_size: int = 1
    vad_filter: bool = True
    # Allowed languages for authoritative finals (ISO 639-1).
    allowed_langs: tuple[str, ...] = ("zh", "en", "ja")

    @classmethod
    def from_env(cls) -> "SttConfig":
        return cls(
            host=_env("STT_HOST", "127.0.0.1"),
            port=_env_int("STT_PORT", 9100),
            model_size=_env("STT_MODEL", "small"),
            device=_env("STT_DEVICE", "cpu"),
            compute_type=_env("STT_COMPUTE_TYPE", "int8"),
            model_cache_dir=_env("STT_MODEL_CACHE", ""),
            max_utterance_ms=_env_int("STT_MAX_UTTERANCE_MS", 30_000),
            max_pcm_bytes=_env_int("STT_MAX_PCM_BYTES", 16000 * 2 * 30),
            max_active_utterances=_env_int("STT_MAX_ACTIVE_UTTERANCES", 16),
            partial_interval_ms=_env_int("STT_PARTIAL_INTERVAL_MS", 800),
            beam_size=_env_int("STT_BEAM_SIZE", 1),
            vad_filter=_env("STT_VAD_FILTER", "1") not in ("0", "false", "False"),
        )
