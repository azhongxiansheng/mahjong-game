"""Real faster-whisper + VAD on redistributable fixtures.

Performance numbers are machine-local baselines, not SLAs.
"""

from __future__ import annotations

import time
from pathlib import Path

import pytest


def _load(path: Path) -> bytes:
    from stt_service.transcriber import WhisperTranscriber

    return WhisperTranscriber.wav_bytes_to_pcm16(path.read_bytes())


@pytest.mark.slow
def test_en_jfk_real_model(transcriber, fixtures_dir):
    path = fixtures_dir / "en_jfk_16k.wav"
    assert path.is_file(), path
    pcm = _load(path)
    t0 = time.perf_counter()
    result = transcriber.transcribe_pcm(pcm, is_final=True)
    wall = time.perf_counter() - t0
    rtf = wall / max(result.duration_before_vad, 1e-6)
    print(
        f"[EN] text={result.text!r} lang={result.lang} "
        f"dur_before={result.duration_before_vad:.3f}s "
        f"dur_after_vad={result.duration_after_vad:.3f}s "
        f"wall={wall:.3f}s rtf={rtf:.3f}"
    )
    assert result.empty_reason is None
    assert result.lang == "en"
    text_l = result.text.lower()
    assert "ask" in text_l or "country" in text_l or "fellow" in text_l
    assert result.duration_after_vad > 0
    assert result.duration_after_vad <= result.duration_before_vad + 0.5


@pytest.mark.slow
def test_zh_real_model(transcriber, fixtures_dir):
    path = fixtures_dir / "zh_zhonghuarenmingongheguo_16k.wav"
    assert path.is_file(), path
    pcm = _load(path)
    t0 = time.perf_counter()
    result = transcriber.transcribe_pcm(pcm, is_final=True)
    wall = time.perf_counter() - t0
    rtf = wall / max(result.duration_before_vad, 1e-6)
    print(
        f"[ZH] text={result.text!r} lang={result.lang} "
        f"dur_before={result.duration_before_vad:.3f}s "
        f"dur_after_vad={result.duration_after_vad:.3f}s "
        f"wall={wall:.3f}s rtf={rtf:.3f}"
    )
    assert result.empty_reason is None
    assert result.lang == "zh"
    assert any(k in result.text for k in ("中国", "中华", "人民", "共和", "国"))


@pytest.mark.slow
def test_ja_real_model(transcriber, fixtures_dir):
    path = fixtures_dir / "ja_tokyo_16k.wav"
    if not path.is_file():
        pytest.skip("ja fixture not yet downloaded")
    pcm = _load(path)
    t0 = time.perf_counter()
    result = transcriber.transcribe_pcm(pcm, is_final=True)
    wall = time.perf_counter() - t0
    rtf = wall / max(result.duration_before_vad, 1e-6)
    print(
        f"[JA] text={result.text!r} lang={result.lang} "
        f"dur_before={result.duration_before_vad:.3f}s "
        f"dur_after_vad={result.duration_after_vad:.3f}s "
        f"wall={wall:.3f}s rtf={rtf:.3f}"
    )
    assert result.empty_reason is None
    assert result.lang == "ja"
    assert result.text.strip()
    assert any(k in result.text for k in ("東京", "とうきょう", "トウキョウ", "Tokyo", "tokyo"))


@pytest.mark.slow
def test_silence_vad_empty(transcriber, fixtures_dir):
    path = fixtures_dir / "silence_2s_16k.wav"
    pcm = _load(path)
    result = transcriber.transcribe_pcm(pcm, is_final=True)
    print(
        f"[SILENCE] text={result.text!r} reason={result.empty_reason} "
        f"dur_after_vad={result.duration_after_vad:.3f}"
    )
    assert not result.text.strip()
    assert result.empty_reason in ("EMPTY", "VAD_NO_SPEECH", "LANG_FILTERED")


@pytest.mark.slow
def test_short_noise_empty(transcriber, fixtures_dir):
    path = fixtures_dir / "noise_150ms_16k.wav"
    pcm = _load(path)
    result = transcriber.transcribe_pcm(pcm, is_final=True)
    print(f"[NOISE] text={result.text!r} reason={result.empty_reason}")
    assert result.empty_reason is not None or not result.text.strip()
