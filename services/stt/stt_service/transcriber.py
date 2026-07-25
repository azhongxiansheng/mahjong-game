"""faster-whisper + Silero VAD wrapper (real model path; no fake text)."""

from __future__ import annotations

import io
import time
import wave
from dataclasses import dataclass
from typing import Any

import numpy as np

from .config import SttConfig


@dataclass
class TranscribeResult:
    text: str
    lang: str
    duration_before_vad: float
    duration_after_vad: float
    wall_ms: int
    empty_reason: str | None = None  # EMPTY | VAD_NO_SPEECH | LANG_FILTERED | None


class WhisperTranscriber:
    """Loads multilingual Whisper `small` once; transcribe PCM16 LE mono 16 kHz."""

    def __init__(self, config: SttConfig, model: Any | None = None) -> None:
        self.config = config
        self._model = model

    def ensure_model(self) -> Any:
        if self._model is not None:
            return self._model
        from faster_whisper import WhisperModel

        kwargs: dict[str, Any] = {
            "device": self.config.device,
            "compute_type": self.config.compute_type,
        }
        if self.config.model_cache_dir:
            kwargs["download_root"] = self.config.model_cache_dir
        # Prefer local cache (no hard-coded user path). Fall back to download if allowed.
        try:
            self._model = WhisperModel(self.config.model_size, local_files_only=True, **kwargs)
        except Exception:
            self._model = WhisperModel(self.config.model_size, local_files_only=False, **kwargs)
        return self._model

    def pcm16_to_float32(self, pcm: bytes) -> np.ndarray:
        if not pcm:
            return np.zeros(0, dtype=np.float32)
        arr = np.frombuffer(pcm, dtype=np.int16).astype(np.float32) / 32768.0
        return arr

    def duration_sec(self, pcm: bytes) -> float:
        if not pcm:
            return 0.0
        return len(pcm) / 2.0 / float(self.config.sample_rate)

    def transcribe_pcm(self, pcm: bytes, *, is_final: bool) -> TranscribeResult:
        """Run real faster-whisper with optional VAD.

        Partial may skip VAD for speed; final always uses vad_filter when enabled.
        """
        dur_before = self.duration_sec(pcm)
        if len(pcm) < self.config.bytes_per_frame:
            return TranscribeResult(
                text="",
                lang="",
                duration_before_vad=dur_before,
                duration_after_vad=0.0,
                wall_ms=0,
                empty_reason="EMPTY",
            )

        model = self.ensure_model()
        audio = self.pcm16_to_float32(pcm)
        t0 = time.perf_counter()
        use_vad = bool(self.config.vad_filter and is_final)
        segments, info = model.transcribe(
            audio,
            language=None,  # multilingual auto-detect
            beam_size=self.config.beam_size if is_final else 1,
            vad_filter=use_vad,
            condition_on_previous_text=False,
            without_timestamps=True,
        )
        texts: list[str] = []
        for seg in segments:
            t = (seg.text or "").strip()
            if t:
                texts.append(t)
        wall_ms = int((time.perf_counter() - t0) * 1000)
        text = " ".join(texts).strip()
        lang = (getattr(info, "language", None) or "").strip().lower()
        # Normalize Chinese variants.
        if lang in ("zh", "chinese", "zh-cn", "zh-tw", "yue"):
            lang = "zh"
        elif lang in ("en", "english"):
            lang = "en"
        elif lang in ("ja", "japanese"):
            lang = "ja"

        dur_after = float(getattr(info, "duration_after_vad", None) or 0.0)
        if not use_vad:
            dur_after = dur_before
        if dur_after <= 0.0 and not text:
            # VAD removed everything or pure silence.
            return TranscribeResult(
                text="",
                lang=lang,
                duration_before_vad=dur_before,
                duration_after_vad=dur_after,
                wall_ms=wall_ms,
                empty_reason="VAD_NO_SPEECH" if use_vad else "EMPTY",
            )
        if not text:
            return TranscribeResult(
                text="",
                lang=lang,
                duration_before_vad=dur_before,
                duration_after_vad=dur_after,
                wall_ms=wall_ms,
                empty_reason="EMPTY",
            )
        if is_final and lang and lang not in self.config.allowed_langs:
            return TranscribeResult(
                text="",
                lang=lang,
                duration_before_vad=dur_before,
                duration_after_vad=dur_after,
                wall_ms=wall_ms,
                empty_reason="LANG_FILTERED",
            )
        if is_final and lang not in self.config.allowed_langs:
            # Unknown / empty lang with text: still reject for authority accumulate.
            return TranscribeResult(
                text="",
                lang=lang or "",
                duration_before_vad=dur_before,
                duration_after_vad=dur_after,
                wall_ms=wall_ms,
                empty_reason="LANG_FILTERED",
            )
        return TranscribeResult(
            text=text,
            lang=lang if lang in self.config.allowed_langs else (lang or ""),
            duration_before_vad=dur_before,
            duration_after_vad=dur_after,
            wall_ms=wall_ms,
            empty_reason=None,
        )

    @staticmethod
    def wav_bytes_to_pcm16(wav_bytes: bytes) -> bytes:
        """Decode a WAV file to raw PCM16 mono (caller should resample if needed)."""
        with wave.open(io.BytesIO(wav_bytes), "rb") as wf:
            channels = wf.getnchannels()
            sampwidth = wf.getsampwidth()
            rate = wf.getframerate()
            n = wf.getnframes()
            raw = wf.readframes(n)
        if sampwidth != 2:
            raise ValueError(f"expected 16-bit PCM, got sampwidth={sampwidth}")
        if channels == 1:
            pcm = raw
        else:
            arr = np.frombuffer(raw, dtype=np.int16).reshape(-1, channels)
            pcm = arr[:, 0].tobytes()
        if rate != 16000:
            # Simple linear resample for fixtures that slipped.
            arr = np.frombuffer(pcm, dtype=np.int16).astype(np.float32)
            duration = len(arr) / float(rate)
            target_len = int(duration * 16000)
            if target_len <= 0:
                return b""
            x_old = np.linspace(0.0, 1.0, num=len(arr), endpoint=False)
            x_new = np.linspace(0.0, 1.0, num=target_len, endpoint=False)
            resampled = np.interp(x_new, x_old, arr).astype(np.int16)
            pcm = resampled.tobytes()
        return pcm
