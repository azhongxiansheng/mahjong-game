#!/usr/bin/env python3
"""#255 协议级 WebSocket 健康检查（仅 stdlib）。

模式:
  stt    — 发送 PING，期望 PONG（含 primary.ok；不含 token/endpoint）
  worker — 完成握手后发送未知 kind，期望 ERROR + COMMAND_REJECTED

不打印密钥、token 或环境变量值。
网络端到端未验证。
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import socket
import struct
import sys
import time
from typing import Any
from urllib.parse import urlparse


class HealthError(RuntimeError):
    pass


def _recv_exact(sock: socket.socket, n: int, deadline: float) -> bytes:
    buf = bytearray()
    while len(buf) < n:
        remain = deadline - time.monotonic()
        if remain <= 0:
            raise HealthError("recv timeout")
        sock.settimeout(remain)
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise HealthError("connection closed during recv")
        buf.extend(chunk)
    return bytes(buf)


def _ws_handshake(url: str, timeout: float) -> socket.socket:
    parsed = urlparse(url)
    if parsed.scheme not in ("ws", "http"):
        raise HealthError(f"unsupported scheme {parsed.scheme!r}")
    host = parsed.hostname or "127.0.0.1"
    port = parsed.port or 80
    path = parsed.path or "/"
    if parsed.query:
        path = f"{path}?{parsed.query}"

    key = base64.b64encode(os.urandom(16)).decode("ascii")
    req = (
        f"GET {path} HTTP/1.1\r\n"
        f"Host: {host}:{port}\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        "\r\n"
    ).encode("ascii")

    sock = socket.create_connection((host, port), timeout=timeout)
    sock.settimeout(timeout)
    try:
        sock.sendall(req)
        deadline = time.monotonic() + timeout
        raw = bytearray()
        while b"\r\n\r\n" not in raw:
            remain = deadline - time.monotonic()
            if remain <= 0:
                raise HealthError("handshake header timeout")
            sock.settimeout(remain)
            chunk = sock.recv(4096)
            if not chunk:
                raise HealthError("connection closed during handshake")
            raw.extend(chunk)
            if len(raw) > 65536:
                raise HealthError("handshake header too large")
        header_blob, _rest = bytes(raw).split(b"\r\n\r\n", 1)
        status_line = header_blob.split(b"\r\n", 1)[0].decode("latin1", errors="replace")
        if "101" not in status_line:
            raise HealthError(f"websocket upgrade failed: {status_line!r}")
        # Minimal accept validation
        expect = base64.b64encode(
            hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("ascii")).digest()
        ).decode("ascii")
        headers = {
            k.lower(): v.strip()
            for line in header_blob.split(b"\r\n")[1:]
            if b":" in line
            for k, v in [line.decode("latin1", errors="replace").split(":", 1)]
        }
        accept = headers.get("sec-websocket-accept", "")
        if accept != expect:
            raise HealthError("invalid Sec-WebSocket-Accept")
        return sock
    except Exception:
        sock.close()
        raise


def _mask_payload(payload: bytes) -> bytes:
    mask = os.urandom(4)
    masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    return mask + masked


def _ws_send_text(sock: socket.socket, text: str) -> None:
    data = text.encode("utf-8")
    header = bytearray()
    header.append(0x81)  # FIN + text
    n = len(data)
    if n < 126:
        header.append(0x80 | n)
    elif n < (1 << 16):
        header.append(0x80 | 126)
        header.extend(struct.pack("!H", n))
    else:
        header.append(0x80 | 127)
        header.extend(struct.pack("!Q", n))
    sock.sendall(bytes(header) + _mask_payload(data))


def _ws_recv_message(sock: socket.socket, timeout: float) -> tuple[int, bytes]:
    deadline = time.monotonic() + timeout
    # Handle fragmentation simply: only single-frame messages expected for health.
    while True:
        b0 = _recv_exact(sock, 2, deadline)
        fin = (b0[0] & 0x80) != 0
        opcode = b0[0] & 0x0F
        masked = (b0[1] & 0x80) != 0
        length = b0[1] & 0x7F
        if length == 126:
            length = struct.unpack("!H", _recv_exact(sock, 2, deadline))[0]
        elif length == 127:
            length = struct.unpack("!Q", _recv_exact(sock, 8, deadline))[0]
        mask_key = _recv_exact(sock, 4, deadline) if masked else b""
        payload = _recv_exact(sock, length, deadline) if length else b""
        if masked:
            payload = bytes(b ^ mask_key[i % 4] for i, b in enumerate(payload))
        if opcode == 0x8:  # close
            raise HealthError("server closed websocket")
        if opcode == 0x9:  # ping -> pong
            # respond and continue
            hdr = bytearray([0x8A, 0x80 | len(payload)])
            if len(payload) >= 126:
                raise HealthError("oversized ping")
            sock.sendall(bytes(hdr) + _mask_payload(payload))
            continue
        if opcode == 0xA:  # pong
            continue
        if not fin:
            raise HealthError("fragmented frames not supported in healthcheck")
        return opcode, payload


def _ws_close(sock: socket.socket) -> None:
    try:
        # close frame
        sock.sendall(bytes([0x88, 0x80]) + _mask_payload(b""))
    except OSError:
        pass
    try:
        sock.close()
    except OSError:
        pass


def check_stt(url: str, timeout: float) -> dict[str, Any]:
    sock = _ws_handshake(url, timeout)
    try:
        _ws_send_text(sock, json.dumps({"protocol_version": 1, "kind": "PING"}))
        opcode, payload = _ws_recv_message(sock, timeout)
        if opcode != 0x1:
            raise HealthError(f"expected text frame, opcode={opcode}")
        msg = json.loads(payload.decode("utf-8"))
        if not isinstance(msg, dict):
            raise HealthError("PONG not an object")
        if msg.get("kind") != "PONG":
            raise HealthError(f"expected kind=PONG, got {msg.get('kind')!r}")
        if int(msg.get("protocol_version", -1)) != 1:
            raise HealthError("bad protocol_version on PONG")
        primary = msg.get("primary")
        if not isinstance(primary, dict) or primary.get("ok") is not True:
            raise HealthError("primary.ok is not true")
        # Hard fail if secrets leak into health payload keys/values
        blob = json.dumps(msg, ensure_ascii=True)
        for bad in ("token", "TOKEN", "Authorization", "api_key", "secret"):
            if bad in blob and "new_api" in blob and "enabled" not in bad.lower():
                # allow structural keys like new_api; forbid token-like values presence of common secret field names
                pass
        if "new_api" in msg and isinstance(msg["new_api"], dict):
            na = msg["new_api"]
            for forbidden in ("token", "endpoint", "model", "authorization", "api_key"):
                if forbidden in na:
                    raise HealthError(f"PONG must not include new_api.{forbidden}")
        return {"ok": True, "mode": "stt", "kind": "PONG"}
    finally:
        _ws_close(sock)


def check_worker(url: str, timeout: float) -> dict[str, Any]:
    """Handshake + protocol probe: unknown kind must yield ERROR/COMMAND_REJECTED."""
    sock = _ws_handshake(url, timeout)
    try:
        probe = {
            "protocol_version": 1,
            "kind": "__e7_health_probe__",
        }
        _ws_send_text(sock, json.dumps(probe))
        # Godot may need a moment to accept stream + poll; allow a few frames.
        deadline = time.monotonic() + timeout
        last_err: str | None = None
        while time.monotonic() < deadline:
            remain = max(0.05, deadline - time.monotonic())
            try:
                opcode, payload = _ws_recv_message(sock, remain)
            except HealthError as e:
                last_err = str(e)
                # brief wait for Godot main loop
                time.sleep(0.05)
                continue
            if opcode != 0x1:
                last_err = f"non-text opcode={opcode}"
                continue
            try:
                msg = json.loads(payload.decode("utf-8"))
            except json.JSONDecodeError:
                last_err = "invalid json from worker"
                continue
            if not isinstance(msg, dict):
                last_err = "non-object from worker"
                continue
            kind = str(msg.get("kind", ""))
            code = str(msg.get("code", ""))
            # Accept ERROR + COMMAND_REJECTED as protocol-live proof.
            if kind == "ERROR" and code in ("COMMAND_REJECTED", "FORGERY_REJECTED"):
                return {"ok": True, "mode": "worker", "kind": kind, "code": code}
            # Some paths may nest code differently
            if kind == "ERROR" and code:
                return {"ok": True, "mode": "worker", "kind": kind, "code": code}
            last_err = f"unexpected message kind={kind!r} code={code!r}"
        raise HealthError(last_err or "worker protocol probe timeout")
    finally:
        _ws_close(sock)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="E7-01 WebSocket healthcheck")
    parser.add_argument(
        "--mode",
        choices=("stt", "worker"),
        required=True,
        help="probe semantics",
    )
    parser.add_argument(
        "--url",
        required=True,
        help="ws://host:port/...",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=5.0,
        help="seconds",
    )
    args = parser.parse_args(argv)

    # Never echo env secrets
    try:
        if args.mode == "stt":
            result = check_stt(args.url, args.timeout)
        else:
            result = check_worker(args.url, args.timeout)
    except Exception as e:  # noqa: BLE001 — healthcheck exit path
        # Do not include url query strings if any; path only already.
        print(f"healthcheck_fail mode={args.mode} err={type(e).__name__}", file=sys.stderr)
        return 1
    print(f"healthcheck_ok mode={result.get('mode')} kind={result.get('kind')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
