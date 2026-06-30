#!/usr/bin/env python3
"""Verify P13 explicit overload/backpressure semantics."""

from __future__ import annotations

import json
import os
import shutil
import signal
import socket
import struct
import subprocess
import threading
import time
import uuid
import zlib
from typing import Any


HOST = "127.0.0.1"
PORT = 7419
DATA_DIR = "backpressure_data"
LOG_PATH = "backpressure_daemon.log"
BINARY = "./target/release/tbackend"
FAILED = 0


def assert_true(condition: bool, message: str) -> None:
    global FAILED
    if condition:
        print(f"PASS: {message}")
    else:
        FAILED += 1
        print(f"FAIL: {message}")


def recvall(sock: socket.socket, size: int) -> bytes:
    chunks = []
    remaining = size
    while remaining > 0:
        chunk = sock.recv(remaining)
        if not chunk:
            raise EOFError("socket closed")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def send_req(sock: socket.socket, req: dict[str, Any], timeout: float = 5.0) -> dict[str, Any]:
    body = json.dumps(req, sort_keys=True, separators=(",", ":")).encode("utf-8")
    frame = struct.pack(">I", len(body)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)
    sock.settimeout(timeout)
    sock.sendall(frame)
    header = recvall(sock, 4)
    length = struct.unpack(">I", header)[0]
    resp_body = recvall(sock, length)
    _crc = recvall(sock, 4)
    return json.loads(resp_body.decode("utf-8"))


def one_req(req: dict[str, Any], timeout: float = 5.0) -> dict[str, Any]:
    with socket.create_connection((HOST, PORT), timeout=3.0) as sock:
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        return send_req(sock, req, timeout)


def make_fact(store: str, key: str, payload: str = "p13") -> dict[str, Any]:
    now = time.time()
    value = {"payload": payload, "key": key}
    return {
        "id": str(uuid.uuid4()),
        "store": store,
        "key": key,
        "value": value,
        "value_hash": str(zlib.crc32(json.dumps(value, sort_keys=True).encode("utf-8"))),
        "transaction_time": now,
        "valid_time": now,
        "schema_version": 1,
    }


def start_daemon() -> subprocess.Popen[Any]:
    shutil.rmtree(DATA_DIR, ignore_errors=True)
    try:
        os.remove(LOG_PATH)
    except FileNotFoundError:
        pass
    log = open(LOG_PATH, "wb")
    proc = subprocess.Popen(
        [
            BINARY,
            "--host",
            HOST,
            "--port",
            str(PORT),
            "--data-dir",
            DATA_DIR,
            "--pool-size",
            "4",
            "--max-inflight-requests",
            "1",
        ],
        stdout=log,
        stderr=log,
    )
    deadline = time.time() + 8
    last_error: BaseException | None = None
    while time.time() < deadline:
        if proc.poll() is not None:
            raise RuntimeError(f"daemon exited early: {proc.returncode}")
        try:
            if one_req({"op": "ping"}).get("ok") is True:
                return proc
        except BaseException as exc:
            last_error = exc
            time.sleep(0.1)
    raise RuntimeError(f"daemon did not become ready: {last_error!r}")


def stop_daemon(proc: subprocess.Popen[Any]) -> int:
    if proc.poll() is None:
        proc.send_signal(signal.SIGINT)
        try:
            proc.wait(timeout=8)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)
    return proc.returncode or 0


def malformed_frame_check() -> None:
    body = json.dumps({"op": "ping"}).encode("utf-8")
    with socket.create_connection((HOST, PORT), timeout=3.0) as sock:
        sock.sendall(struct.pack(">I", len(body)) + body + struct.pack(">I", 0))
        sock.settimeout(1.0)
        try:
            data = sock.recv(4)
        except socket.timeout:
            data = b""
    assert_true(data == b"", "invalid CRC closes or gives no response")
    assert_true(one_req({"op": "ping"}).get("ok") is True, "good ping works after malformed frame")


def preseed_large_store() -> None:
    payload = "x" * 65536
    with socket.create_connection((HOST, PORT), timeout=3.0) as sock:
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        for i in range(512):
            resp = send_req(sock, {"op": "write_fact", "fact": make_fact("p13_big", f"k-{i}", payload)}, timeout=10.0)
            if resp.get("ok") is not True:
                raise RuntimeError(f"preseed failed at {i}: {resp}")


def hold_one_inflight_request() -> socket.socket:
    sock = socket.create_connection((HOST, PORT), timeout=3.0)
    sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1024)
    body = json.dumps({"op": "facts_for", "store": "p13_big"}, sort_keys=True, separators=(",", ":")).encode("utf-8")
    frame = struct.pack(">I", len(body)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)
    sock.sendall(frame)
    time.sleep(0.3)
    return sock


def force_overload() -> dict[str, Any]:
    found: dict[str, Any] = {}
    lock = threading.Lock()
    stop_at = time.time() + 5.0

    def attempt(thread_id: int) -> None:
        nonlocal found
        idx = 0
        while time.time() < stop_at:
            with lock:
                if found:
                    return
            key = f"rejected-{thread_id}-{idx}"
            fact = make_fact("p13_overload_probe", key)
            try:
                resp = one_req({"op": "write_fact", "fact": fact}, timeout=3.0)
            except BaseException:
                idx += 1
                continue
            if resp.get("error_code") == "overloaded":
                with lock:
                    if not found:
                        found = {"key": key, "fact": fact, "resp": resp}
                return
            idx += 1

    threads = [threading.Thread(target=attempt, args=(i,), daemon=True) for i in range(8)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    return found


def main() -> int:
    proc = start_daemon()
    try:
        assert_true(one_req({"op": "ping"}).get("ok") is True, "low-load ping succeeds")

        accepted = make_fact("p13_low_load", "accepted")
        assert_true(one_req({"op": "write_fact", "fact": accepted}).get("ok") is True, "low-load write succeeds")
        latest = one_req({"op": "latest_for", "store": "p13_low_load", "key": "accepted"})
        assert_true(latest.get("fact", {}).get("id") == accepted["id"], "accepted write is readable")

        duplicate = make_fact("p13_duplicate", "same-id")
        assert_true(one_req({"op": "write_fact", "fact": duplicate}).get("ok") is True, "first duplicate test write succeeds")
        assert_true(one_req({"op": "write_fact", "fact": duplicate}).get("ok") is True, "same fact id retry is accepted")
        dup_size = one_req({"op": "size", "store": "p13_duplicate"})
        assert_true(dup_size.get("size") == 2, "duplicate fact id appends again in current source semantics")

        malformed_frame_check()
        preseed_large_store()
        blocker = hold_one_inflight_request()
        try:
            rejected = force_overload()
        finally:
            blocker.close()

        assert_true(bool(rejected), "overload rejection can be forced deterministically")
        if rejected:
            resp = rejected["resp"]
            assert_true(resp.get("ok") is False, "overload response has ok=false")
            assert_true(resp.get("error_code") == "overloaded", "overload response has error_code=overloaded")
            assert_true(resp.get("committed") is False, "overload response declares committed=false")
            probe = one_req({"op": "latest_for", "store": "p13_overload_probe", "key": rejected["key"]})
            assert_true(probe.get("fact") is None, "rejected-before-commit write did not mutate its key")

        metrics = one_req({"op": "metrics"})
        assert_true(metrics.get("overload_rejections", 0) >= 1, "metrics expose overload_rejections")
        assert_true(one_req({"op": "ping"}).get("ok") is True, "daemon still accepts good requests after overload")
    finally:
        exit_code = stop_daemon(proc)
        assert_true(exit_code == 0, "daemon stopped cleanly")
        shutil.rmtree(DATA_DIR, ignore_errors=True)
        try:
            os.remove(LOG_PATH)
        except FileNotFoundError:
            pass

    if FAILED:
        print(f"FAILURES: {FAILED}")
        return 1
    print("ALL BACKPRESSURE TESTS PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
