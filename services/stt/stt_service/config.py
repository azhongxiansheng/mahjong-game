"""Runtime config via environment variables; secrets (token) are redacted from repr.

New-api credentials use dedicated STT_NEW_API_* vars only — never silent
reuse of asset-generation OPENAI_* env vars.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field


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
    # Primary logical timeout (ms). STT owns this clock; not RewardWindow.
    primary_timeout_ms: int = 30_000
    # OpenAI-compatible / new-api backup (disabled unless all required set).
    new_api_endpoint: str = ""
    new_api_model: str = ""
    new_api_token: str = field(default="", repr=False)
    new_api_timeout_ms: int = 10_000
    circuit_failure_threshold: int = 3
    circuit_cooldown_ms: int = 30_000

    @property
    def new_api_enabled(self) -> bool:
        return bool(self.new_api_endpoint and self.new_api_model and self.new_api_token)

    def __repr__(self) -> str:
        # Explicit: never leak token via default dataclass repr.
        return (
            "SttConfig("
            f"host={self.host!r}, port={self.port}, model_size={self.model_size!r}, "
            f"device={self.device!r}, primary_timeout_ms={self.primary_timeout_ms}, "
            f"new_api_enabled={self.new_api_enabled}, "
            f"new_api_timeout_ms={self.new_api_timeout_ms}, "
            f"circuit_failure_threshold={self.circuit_failure_threshold}, "
            f"circuit_cooldown_ms={self.circuit_cooldown_ms})"
        )

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
            primary_timeout_ms=_env_int("STT_PRIMARY_TIMEOUT_MS", 30_000),
            new_api_endpoint=_env("STT_NEW_API_ENDPOINT", ""),
            new_api_model=_env("STT_NEW_API_MODEL", ""),
            new_api_token=_env("STT_NEW_API_TOKEN", ""),
            new_api_timeout_ms=_env_int("STT_NEW_API_TIMEOUT_MS", 10_000),
            circuit_failure_threshold=_env_int("STT_CIRCUIT_FAILURE_THRESHOLD", 3),
            circuit_cooldown_ms=_env_int("STT_CIRCUIT_COOLDOWN_MS", 30_000),
        )
