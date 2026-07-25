from __future__ import annotations

from stt_service.protocol import (
    KIND_TRANSCRIPT_FINAL,
    PROTOCOL_VERSION,
    SOURCE,
    make_final,
    make_partial,
    validate_commit,
    validate_start,
)


def test_validate_start_ok():
    meta, err = validate_start(
        {
            "protocol_version": 1,
            "kind": "UTTERANCE_START",
            "room_id": "r1",
            "seat": 0,
            "hand_seq": 1,
            "window_id": "w1",
            "utterance_id": "u1",
        }
    )
    assert err is None
    assert meta["room_id"] == "r1"
    assert meta["seat"] == 0


def test_validate_commit_requires_ptt_seq():
    meta, err = validate_commit(
        {
            "protocol_version": 1,
            "kind": "UTTERANCE_COMMIT",
            "room_id": "r1",
            "seat": 0,
            "hand_seq": 1,
            "window_id": "w1",
            "utterance_id": "u1",
        }
    )
    assert meta is None
    assert err == "INVALID_PTT_END_SERVER_SEQ"


def test_final_schema_fields():
    msg = make_final(
        room_id="r1",
        seat=2,
        hand_seq=3,
        window_id="w9",
        utterance_id="utt",
        ptt_end_server_seq=88,
        lang="zh",
        text="你好",
    )
    assert msg["kind"] == KIND_TRANSCRIPT_FINAL
    assert msg["protocol_version"] == PROTOCOL_VERSION
    assert msg["source"] == SOURCE
    assert msg["is_final"] is True
    assert msg["ptt_end_server_seq"] == 88
    assert msg["lang"] == "zh"
    for k in (
        "room_id",
        "seat",
        "hand_seq",
        "window_id",
        "utterance_id",
        "text",
    ):
        assert k in msg


def test_partial_not_final():
    msg = make_partial(
        room_id="r",
        seat=0,
        hand_seq=0,
        window_id="w",
        utterance_id="u",
        ptt_end_server_seq=None,
        lang="en",
        text="hi",
    )
    assert msg["is_final"] is False
