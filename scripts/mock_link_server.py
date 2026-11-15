#!/usr/bin/env python3
"""Local AgentHUD LAN protocol server used to exercise the Flutter mobile UI.

This is a development fixture, not part of the shipped product. It speaks just
enough of docs/lan-monitoring.md for the mobile client to pair and render a
session list, so UI changes can be reviewed on the Android emulator without a
running Windows/macOS AgentHUD.

Usage:
    python mock_link_server.py --port 61051
    python mock_link_server.py --port 61051 --scenario empty

The emulator reaches the host loopback through 10.0.2.2, so pair with
address 10.0.2.2 and the port printed below.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import secrets
import ssl
import subprocess
import sys
import tempfile
import threading
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

DEVICE_NAME = "WL-PC"
INSTANCE_ID = "mock-instance-0001"
CODE = "123456"
PROTOCOL = 1

# Capabilities the mobile client understands: refresh, write, prompt, images,
# conversation. The list below matches what the Windows build advertises today.
CAPABILITIES = ["monitor", "refresh", "write", "prompt", "images", "conversation"]


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def minutes_ago(minutes: int) -> str:
    return (
        datetime.now(timezone.utc).replace(microsecond=0) - timedelta(minutes=minutes)
    ).isoformat()


def build_sessions(scenario: str) -> list[dict]:
    if scenario == "empty":
        return []

    sessions = [
        {
            "id": "sess-claude-hud",
            "provider": "Claude",
            "status": "Working",
            "confidence": "High",
            "title": "处理 Agent-HUD 项目",
            "projectName": "Agent-HUD",
            "currentAction": "正在重写列表刷新逻辑",
            "currentFiles": ["Windows/src/AgentHUD.Windows/MainWindow.xaml"],
            "startedAt": minutes_ago(24),
            "lastActivityAt": minutes_ago(0),
            "completedAt": None,
            "isLive": True,
            "gitBranch": "main",
            "gitChangedFiles": 14,
            "gitInsertions": 741,
            "gitDeletions": 542,
            "summary": None,
            "isImportant": True,
            "titleSource": "AI",
            "hasCustomTitle": False,
            "latestPrompt": {
                "text": "这个是真的丑啊，他是方框还是圆的，而且每次刷新，都会闪烁",
                "sentAt": minutes_ago(3),
                "images": [],
            },
            "runs": [],
            "conversation": {"enabled": True, "state": "ready", "reason": None},
        },
        {
            "id": "sess-claude-windows",
            "provider": "Claude",
            "status": "WaitingUser",
            "confidence": "High",
            "title": "处理 Windows 项目",
            "projectName": "Windows",
            "currentAction": "等待确认是否覆盖已有改动",
            "currentFiles": [
                "Windows/src/AgentHUD.Windows/App.xaml",
                "Windows/src/AgentHUD.Windows/MainWindow.xaml.cs",
            ],
            "startedAt": minutes_ago(52),
            "lastActivityAt": minutes_ago(2),
            "completedAt": None,
            "isLive": True,
            "gitBranch": "main",
            "gitChangedFiles": 5,
            "gitInsertions": 120,
            "gitDeletions": 33,
            "summary": None,
            "isImportant": False,
            "titleSource": "Automatic",
            "hasCustomTitle": False,
            "latestPrompt": None,
            "runs": [],
            "conversation": {"enabled": True, "state": "waitingUser", "reason": None},
        },
        {
            "id": "sess-codex-mobile",
            "provider": "Codex",
            "status": "Working",
            "confidence": "Medium",
            "title": "给手机端做视觉统一",
            "projectName": "Agent-HUD",
            "currentAction": "正在对齐圆角与配色 token",
            "currentFiles": ["mobile/lib/theme.dart", "mobile/lib/widgets/hud_chips.dart"],
            "startedAt": minutes_ago(11),
            "lastActivityAt": minutes_ago(1),
            "completedAt": None,
            "isLive": True,
            "gitBranch": "feature/mobile-polish",
            "gitChangedFiles": 3,
            "gitInsertions": 88,
            "gitDeletions": 12,
            "summary": None,
            "isImportant": False,
            "titleSource": "AI",
            "hasCustomTitle": False,
            "latestPrompt": None,
            "runs": [],
            "conversation": {"enabled": True, "state": "ready", "reason": None},
        },
        {
            "id": "sess-opencode-tools",
            "provider": "OpenCode",
            "status": "Completed",
            "confidence": "High",
            "title": "实现 wl 项目",
            "projectName": "wl",
            "currentAction": "本轮处理已完成",
            "currentFiles": [],
            "startedAt": minutes_ago(1500),
            "lastActivityAt": minutes_ago(1380),
            "completedAt": minutes_ago(1380),
            "isLive": False,
            "gitBranch": None,
            "gitChangedFiles": None,
            "gitInsertions": None,
            "gitDeletions": None,
            "summary": "补齐了三处状态映射并跑通全部测试。",
            "isImportant": False,
            "titleSource": "Automatic",
            "hasCustomTitle": True,
            "latestPrompt": None,
            "runs": [
                {
                    "id": "run-1",
                    "objective": "实现 wl 项目的会话解析",
                    "summary": "新增解析器并接入状态判断",
                    "actions": ["新增 OpenCode 适配器", "补充单元测试"],
                    "filesChanged": ["mobile/lib/models.dart"],
                    "completedAt": minutes_ago(1380),
                    "status": "Completed",
                }
            ],
            "conversation": {"enabled": True, "state": "idle", "reason": None},
        },
        {
            "id": "sess-pi-planb",
            "provider": "Pi",
            "status": "Failed",
            "confidence": "Low",
            "title": "处理 PLAN-B 项目",
            "projectName": "PLAN-B",
            "currentAction": "读取配置失败",
            "currentFiles": [],
            "startedAt": minutes_ago(2900),
            "lastActivityAt": minutes_ago(2880),
            "completedAt": minutes_ago(2880),
            "isLive": False,
            "gitBranch": None,
            "gitChangedFiles": None,
            "gitInsertions": None,
            "gitDeletions": None,
            "summary": "配置文件缺失，已中止。",
            "isImportant": False,
            "titleSource": "Automatic",
            "hasCustomTitle": False,
            "latestPrompt": None,
            "runs": [],
            "conversation": {"enabled": False, "state": "unavailable", "reason": "当前来源不支持会话"},
        },
        {
            "id": "sess-claude-idle",
            "provider": "Claude",
            "status": "Idle",
            "confidence": "High",
            "title": "处理 wl 项目 Agent 筛选",
            "projectName": "wl",
            "currentAction": "会话仍保留，等待下一次任务",
            "currentFiles": [],
            "startedAt": minutes_ago(3000),
            "lastActivityAt": minutes_ago(2960),
            "completedAt": None,
            "isLive": False,
            "gitBranch": None,
            "gitChangedFiles": None,
            "gitInsertions": None,
            "gitDeletions": None,
            "summary": None,
            "isImportant": False,
            "titleSource": "Automatic",
            "hasCustomTitle": False,
            "latestPrompt": None,
            "runs": [],
            "conversation": {"enabled": True, "state": "idle", "reason": None},
        },
    ]
    return sessions


class MockState:
    def __init__(self, scenario: str) -> None:
        self.scenario = scenario
        self.revision = 1
        self.privacy = False
        self.token = secrets.token_urlsafe(24)
        self.device_id = "mock-device"
        self.lock = threading.Lock()
        self.sessions = build_sessions(scenario)

    def bump(self) -> None:
        with self.lock:
            self.revision += 1


def make_self_signed_cert(directory: Path) -> tuple[Path, Path, str]:
    """Create a throwaway certificate and return its SHA-256 fingerprint."""
    key = directory / "key.pem"
    cert = directory / "cert.pem"
    try:
        from cryptography import x509  # type: ignore
        from cryptography.hazmat.primitives import hashes, serialization  # type: ignore
        from cryptography.hazmat.primitives.asymmetric import rsa  # type: ignore
        from cryptography.x509.oid import NameOID  # type: ignore
    except ImportError:
        _openssl_cert(key, cert)
    else:
        private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        subject = issuer = x509.Name(
            [x509.NameAttribute(NameOID.COMMON_NAME, "AgentHUD Mock")]
        )
        now = datetime.now(timezone.utc)
        certificate = (
            x509.CertificateBuilder()
            .subject_name(subject)
            .issuer_name(issuer)
            .public_key(private_key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(now - timedelta(days=1))
            .not_valid_after(now + timedelta(days=365))
            .add_extension(
                x509.SubjectAlternativeName(
                    [
                        x509.DNSName("localhost"),
                        x509.IPAddress(__import__("ipaddress").ip_address("127.0.0.1")),
                        x509.IPAddress(__import__("ipaddress").ip_address("10.0.2.2")),
                    ]
                ),
                critical=False,
            )
            .sign(private_key, hashes.SHA256())
        )
        key.write_bytes(
            private_key.private_bytes(
                encoding=serialization.Encoding.PEM,
                format=serialization.PrivateFormat.TraditionalOpenSSL,
                encryption_algorithm=serialization.NoEncryption(),
            )
        )
        cert.write_bytes(certificate.public_bytes(serialization.Encoding.PEM))

    der = ssl.PEM_cert_to_DER_cert(cert.read_text())
    return key, cert, hashlib.sha256(der).hexdigest().upper()


def _openssl_cert(key: Path, cert: Path) -> None:
    subprocess.run(
        [
            "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-keyout", str(key), "-out", str(cert), "-days", "365",
            "-subj", "/CN=AgentHUD Mock",
        ],
        check=True,
        capture_output=True,
    )


class Handler(BaseHTTPRequestHandler):
    state: MockState
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))
        sys.stderr.flush()

    # -- helpers ---------------------------------------------------------
    def _send(self, status: int, payload: dict | None, extra: dict | None = None) -> None:
        body = b"" if payload is None else json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        for key, value in (extra or {}).items():
            self.send_header(key, value)
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _read_json(self) -> dict:
        # Dart's HttpClient sends request bodies with Transfer-Encoding: chunked
        # rather than Content-Length, so both framings have to be handled or the
        # unread body bytes get parsed as the next request line.
        if "chunked" in (self.headers.get("Transfer-Encoding") or "").lower():
            raw = self._read_chunked()
        else:
            length = int(self.headers.get("Content-Length") or 0)
            raw = self.rfile.read(length) if length > 0 else b""
        if not raw:
            return {}
        try:
            return json.loads(raw.decode())
        except (ValueError, UnicodeDecodeError):
            return {}

    def _read_chunked(self) -> bytes:
        chunks: list[bytes] = []
        while True:
            line = self.rfile.readline(65536).strip()
            if not line:
                break
            try:
                size = int(line.split(b";", 1)[0], 16)
            except ValueError:
                break
            if size == 0:
                # Consume the trailing CRLF after the last chunk.
                self.rfile.readline(65536)
                break
            chunks.append(self.rfile.read(size))
            self.rfile.readline(65536)
        return b"".join(chunks)

    def _authorized(self) -> bool:
        header = self.headers.get("Authorization") or ""
        if not header.startswith("Bearer "):
            return False
        return header[len("Bearer "):].strip() == f"{self.state.device_id}.{self.state.token}"

    def _pairing_payload(self) -> dict:
        return {
            "deviceId": self.state.device_id,
            "token": self.state.token,
            "instanceId": INSTANCE_ID,
            "instanceName": DEVICE_NAME,
            "protocol": PROTOCOL,
            "capabilities": CAPABILITIES,
            "fingerprint": self.server.fingerprint,
            "addresses": ["10.0.2.2"],
            "port": self.server.server_address[1],
        }

    # -- routes ----------------------------------------------------------
    def do_POST(self) -> None:
        path = self.path.split("?")[0]
        body = self._read_json()

        if path == "/v1/pair/verify-code":
            digits = "".join(ch for ch in str(body.get("code") or "") if ch.isdigit())
            if digits != CODE:
                self._send(401, {"error": "invalid_code"})
                return
            print(
                f"[pair] code accepted for device {body.get('deviceName')!r}",
                file=sys.stderr,
            )
            self._send(200, self._pairing_payload())
            return

        if path == "/v1/pair/complete":
            self._send(200, self._pairing_payload())
            return

        if not self._authorized():
            self._send(401, {"error": "unauthorized"})
            return

        if path == "/v1/refresh":
            self.state.bump()
            self._send(200, {"ok": True})
            return

        self._send(404, {"error": "not_found"})

    def do_GET(self) -> None:
        path = self.path.split("?")[0]
        if not self._authorized():
            self._send(401, {"error": "unauthorized"})
            return

        if path == "/v1/status":
            self._send(
                200,
                {
                    "protocol": PROTOCOL,
                    "instanceId": INSTANCE_ID,
                    "instanceName": DEVICE_NAME,
                    "capabilities": CAPABILITIES,
                    "revision": self.state.revision,
                    "scannedAt": now_iso(),
                    "serverTime": now_iso(),
                    "privacyMode": self.state.privacy,
                    "fingerprint": self.server.fingerprint,
                    "addresses": ["10.0.2.2"],
                    "port": self.server.server_address[1],
                },
            )
            return

        if path == "/v1/sessions":
            sessions = self.state.sessions
            payload = {
                "revision": self.state.revision,
                "scannedAt": now_iso(),
                "sessions": sessions,
            }
            etag = '"%s"' % hashlib.sha256(
                json.dumps(payload, sort_keys=True).encode()
            ).hexdigest()[:32]
            if self.headers.get("If-None-Match") == etag:
                self.send_response(304)
                self.send_header("ETag", etag)
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            self._send(200, payload, {"ETag": etag})
            return

        if path.startswith("/v1/sessions/"):
            wanted = path.rsplit("/", 1)[-1]
            for session in self.state.sessions:
                if session["id"] == wanted:
                    self._send(200, session)
                    return
            self._send(404, {"error": "session_not_found"})
            return

        self._send(404, {"error": "not_found"})


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=61051)
    parser.add_argument(
        "--scenario",
        default="default",
        choices=["default", "empty"],
        help="default renders a mixed session list; empty shows the empty state",
    )
    parser.add_argument(
        "--cert-dir",
        default=None,
        help="reuse a directory holding key.pem/cert.pem instead of generating one",
    )
    args = parser.parse_args()

    cert_dir = Path(args.cert_dir) if args.cert_dir else Path(tempfile.mkdtemp(prefix="hud-mock-"))
    cert_dir.mkdir(parents=True, exist_ok=True)
    key, cert, fingerprint = make_self_signed_cert(cert_dir)
    if args.cert_dir:
        der = ssl.PEM_cert_to_DER_cert(cert.read_text())
        fingerprint = hashlib.sha256(der).hexdigest().upper()

    state = MockState(args.scenario)
    Handler.state = state
    server = ThreadingHTTPServer(("0.0.0.0", args.port), Handler)
    server.fingerprint = fingerprint
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(certfile=str(cert), keyfile=str(key))
    server.socket = context.wrap_socket(server.socket, server_side=True)

    print("AgentHUD mock link server", file=sys.stderr)
    print(f"  listen      : 0.0.0.0:{args.port} (https)", file=sys.stderr)
    print(f"  scenario    : {args.scenario} ({len(state.sessions)} sessions)", file=sys.stderr)
    print(f"  pairing code: {CODE}", file=sys.stderr)
    print("  emulator address: 10.0.2.2", file=sys.stderr)
    print(f"  fingerprint : {fingerprint}", file=sys.stderr)
    print(f"  cert dir    : {cert_dir}", file=sys.stderr)
    sys.stderr.flush()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nstopping", file=sys.stderr)
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
