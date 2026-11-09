#!/usr/bin/env python3
"""Dependency-free HTTP, cookie, upload, WebSocket and concurrency integration probe."""
import argparse
import base64
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import secrets
import socket
import struct
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen


def check(condition, description):
    if not condition:
        raise AssertionError(description)


def http(base, path, method="GET", data=None, headers=None):
    req = Request(base + path, data=data, method=method, headers=headers or {})
    try:
        with urlopen(req, timeout=6) as res:
            return res.status, dict(res.headers), res.read()
    except HTTPError as ex:
        return ex.code, dict(ex.headers), ex.read()


def read_until(sock, delimiter, maximum=8192):
    data = b""
    while delimiter not in data:
        block = sock.recv(4096)
        if not block:
            raise RuntimeError("WebSocket peer closed before handshake")
        data += block
        if len(data) > maximum:
            raise RuntimeError("WebSocket handshake exceeds maximum")
    return data


def ws_send(sock, opcode, data):
    check(len(data) < 126, "test frame must be small")
    mask = secrets.token_bytes(4)
    masked = bytes(value ^ mask[i % 4] for i, value in enumerate(data))
    sock.sendall(bytes([0x80 | opcode, 0x80 | len(data)]) + mask + masked)


def ws_frame(sock):
    head = sock.recv(2)
    check(len(head) == 2, "truncated WebSocket response")
    b0, b1 = head
    check((b1 & 0x80) == 0, "server frame must not be masked")
    n = b1 & 127
    check(n < 126, "unexpected large WebSocket control frame")
    content = b""
    while len(content) < n:
        chunk = sock.recv(n - len(content))
        if not chunk:
            raise RuntimeError("WebSocket truncated frame payload")
        content += chunk
    return b0 & 0x0F, content


def websocket_probe(host, port):
    key = base64.b64encode(secrets.token_bytes(16)).decode("ascii")
    handshake = (
        "GET /__mojara_dev/ws HTTP/1.1\r\n"
        f"Host: {host}:{port}\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        f"Origin: http://{host}:{port}\r\n"
        "\r\n"
    ).encode("ascii")
    with socket.create_connection((host, port), timeout=5) as sock:
        sock.settimeout(5)
        sock.sendall(handshake)
        reply = read_until(sock, b"\r\n\r\n")
        check(reply.startswith(b"HTTP/1.1 101"), f"upgrade failed: {reply[:100]!r}")
        expected = base64.b64encode(hashlib.sha1(
            (key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()
        ).digest())
        check(expected.lower() in reply.lower(), "Sec-WebSocket-Accept mismatch")
        ws_send(sock, 0x1, b"hello-websocket")
        ws_send(sock, 0x9, b"ping-ci")
        code, payload = ws_frame(sock)
        check((code, payload) == (0xA, b"ping-ci"), "WebSocket ping/pong failed")
        ws_send(sock, 0x8, struct.pack("!H", 1000))
        code, _ = ws_frame(sock)
        check(code == 0x8, "WebSocket close handshake not acknowledged")
        print("PASS: RFC6455 handshake, masked text, ping/pong, close (Mojara dev reload handler)")


def functional_probe(base, host, port, work):
    code, _, body = http(base, "/health")
    check(code == 200 and json.loads(body)["status"] == "ok", "health endpoint failed")

    code, _, body = http(base, "/session/verify")
    check(code == 401, "anonymous session unexpectedly authorized")
    code, headers, body = http(base, "/session/issue")
    check(code == 200 and body == b"session-issued", "signed cookie was not issued")
    cookie = headers.get("Set-Cookie", "").split(";", 1)[0]
    check(cookie.startswith("mojara_ci="), "signed cookie missing")
    code, _, body = http(base, "/session/verify", headers={"Cookie": cookie})
    check(code == 200 and body == b"session-verified", "signed session round trip failed")
    code, _, body = http(base, "/session/verify", headers={"Cookie": cookie + "tampered"})
    check(code == 401, "tampered cookie was accepted")
    print("PASS: signed session issue, valid round trip, anonymous + tampered rejection")

    code, _, body = http(
        base, "/form", method="POST", data=b"name=O%27Brien+CI",
        headers={"Content-Type": "application/x-www-form-urlencoded"}
    )
    check(code == 200 and body == b"name:O'Brien CI", "URL-encoded form parse failed")
    print("PASS: URL-encoded form values and escaping")

    token = "ci-upload-token-32-characters-minimum"
    boundary = "MojoIntegrationBoundary2026"
    payload = b"ARM64 payload verified."
    multipart = (
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"probe.txt\"\r\n"
        "Content-Type: text/plain\r\n\r\n"
    ).encode() + payload + f"\r\n--{boundary}--\r\n".encode()
    headers = {"Content-Type": "multipart/form-data; boundary=" + boundary}
    code, _, _ = http(base, "/upload", method="POST", data=multipart, headers=headers)
    check(code == 403, f"unauthorized upload status: {code}")
    headers["X-Mojara-Upload-Token"] = token
    code, _, body = http(base, "/upload", method="POST", data=multipart, headers=headers)
    check(code == 201, f"valid upload status: {code} ({body[:120]!r})")
    record = json.loads(body)
    path = work / "private_uploads" / record["stored_name"]
    check(record["bytes"] == len(payload), "upload size mismatch")
    if not path.is_file() or path.read_bytes() != payload:
        print("UPLOAD_DEBUG", {
            "record": record, "expected_path": str(path),
            "exists": path.exists(),
            "files": [str(p) for p in work.rglob("upload-*")],
            "actual_bytes": repr(path.read_bytes()) if path.is_file() else None,
            "expected_bytes": repr(payload),
            "cwd": str(Path.cwd()),
        }, flush=True)
    check(path.is_file() and path.read_bytes() == payload, "saved upload bytes differ")
    check((path.stat().st_mode & 0o777) == 0o600, "upload permissions not 0600")
    oversize = b"X" * 1200
    large = multipart.replace(payload, oversize)
    code, _, _ = http(base, "/upload", method="POST", data=large, headers=headers)
    check(code == 413, f"oversized upload not rejected: {code}")
    print("PASS: multipart authenticated upload, persistence, permissions, oversize rejection")

    def multipart_part(filename, content, media="text/plain"):
        return (
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="files"; filename="{filename}"\r\n'
            f"Content-Type: {media}\r\n\r\n"
        ).encode() + content + b"\r\n"

    alpha, beta = b"alpha-Mojara", b"beta-Mojara"
    multi = (multipart_part("first.txt", alpha)
             + multipart_part("second.txt", beta)
             + f"--{boundary}--\r\n".encode())
    multi_headers = {"Content-Type": "multipart/form-data; boundary=" + boundary}
    code, _, _ = http(base, "/uploads", method="POST", data=multi, headers=multi_headers)
    check(code == 403, "unauthorized multi-upload was accepted")
    multi_headers["X-Mojara-Upload-Token"] = token
    code, _, body = http(base, "/uploads", method="POST", data=multi, headers=multi_headers)
    check(code == 201, f"valid multi-upload status: {code} ({body[:180]!r})")
    batch = json.loads(body)
    check(batch["count"] == 2 and len(batch["files"]) == 2, "multi-upload count mismatch")
    for record, expected in zip(batch["files"], (alpha, beta)):
        check(record["bytes"] == len(expected), "multi-upload file size mismatch")
        check(record["content_type"] == "text/plain", "multi-upload MIME mismatch")
        candidate = work / "private_uploads" / record["stored_name"]
        check(candidate.is_file() and candidate.read_bytes() == expected,
              f"multi-upload stored content differs: {record}")
        check((candidate.stat().st_mode & 0o777) == 0o600, "multi-upload permissions not private")
    present = {x.name for x in (work / "private_uploads").glob("upload-*")}
    bad = (multipart_part("first.txt", alpha)
           + multipart_part("second.txt", beta)
           + multipart_part("third.txt", b"too-many")
           + f"--{boundary}--\r\n".encode())
    code, _, _ = http(base, "/uploads", method="POST", data=bad, headers=multi_headers)
    check(code == 413, f"multi-upload exceeding file count was not rejected: {code}")
    check(present == {x.name for x in (work / "private_uploads").glob("upload-*")},
          "failed atomic multi-upload left partial files")
    print("PASS: authenticated atomic multi-file upload, metadata, permissions, file-count policy")

    websocket_probe(host, port)


def concurrency_probe(base, n=300, workers=12):
    started = time.perf_counter()

    def request_one(_):
        code, _, body = http(base, "/health")
        return code == 200 and body == b'{"status":"ok","framework":"Mojara"}'

    with ThreadPoolExecutor(max_workers=workers) as ex:
        result = list(ex.map(request_one, range(n)))
    check(all(result), f"HTTP concurrency failed: {result.count(False)} of {n}")
    elapsed = time.perf_counter() - started
    print(f"PASS: {n} / {n} HTTP requests, {workers} concurrent workers in {elapsed:.2f}s")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=18786)
    parser.add_argument("--work", type=Path, required=True)
    args = parser.parse_args()
    base = f"http://{args.host}:{args.port}"
    functional_probe(base, args.host, args.port, args.work)
    concurrency_probe(base)
