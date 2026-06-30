#!/usr/bin/env python3
"""Verify P15 write_fact_once idempotent retry semantics."""

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
PORT = 7421
DATA_DIR = "idempotent_write_data"
LOG_PATH = "idempotent_write_daemon.log"
BINARY = "./target/release/tbackend"
FAILED = 0


def assert_true(condition: bool, message: str) -> None:
    global FAILED
    if condition:
        print(f"PASS: {message}")
    else:
        FAILED += 1
        print(f"FAIL: {message}")


def encode_frame(req: dict[str, Any]) -> bytes:
    body = json.dumps(req, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return struct.pack(">I", len(body)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


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
    sock.settimeout(timeout)
    sock.sendall(encode_frame(req))
    header = recvall(sock, 4)
    length = struct.unpack(">I", header)[0]
    resp_body = recvall(sock, length)
    _crc = recvall(sock, 4)
    return json.loads(resp_body.decode("utf-8"))


def one_req(req: dict[str, Any], timeout: float = 5.0) -> dict[str, Any]:
    with socket.create_connection((HOST, PORT), timeout=3.0) as sock:
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        return send_req(sock, req, timeout)


def value_hash(value: dict[str, Any]) -> str:
    body = json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return str(zlib.crc32(body) & 0xFFFFFFFF)


def make_fact(store: str, key: str, payload: str = "p15") -> dict[str, Any]:
    now = time.time()
    value = {"payload": payload, "key": key}
    return {
        "id": str(uuid.uuid4()),
        "store": store,
        "key": key,
        "value": value,
        "value_hash": value_hash(value),
        "transaction_time": now,
        "valid_time": now,
        "schema_version": 1,
    }


def start_daemon(reset_data: bool = True) -> subprocess.Popen[Any]:
    if reset_data:
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
            "8",
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


def store_size(store: str) -> int:
    resp = one_req({"op": "size", "store": store})
    if resp.get("ok") is not True:
        raise RuntimeError(f"size failed: {resp}")
    return int(resp.get("size", -1))


def facts_for_key(store: str, key: str) -> list[dict[str, Any]]:
    resp = one_req({"op": "facts_for", "store": store, "key": key})
    if resp.get("ok") is not True:
        raise RuntimeError(f"facts_for failed: {resp}")
    return resp.get("facts", [])


def write_once(fact: dict[str, Any]) -> dict[str, Any]:
    return one_req({"op": "write_fact_once", "fact": fact})


def conflict_variant(fact: dict[str, Any], key: str | None = None) -> dict[str, Any]:
    variant = dict(fact)
    if key is not None:
        variant["key"] = key
    variant["value"] = {"payload": "conflict", "key": variant["key"]}
    variant["value_hash"] = value_hash(variant["value"])
    return variant


def send_once_without_observing_ack(fact: dict[str, Any]) -> None:
    with socket.create_connection((HOST, PORT), timeout=3.0) as sock:
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        sock.sendall(encode_frame({"op": "write_fact_once", "fact": fact}))
        time.sleep(0.05)


def assert_single_fact(store: str, key: str, fact_id: str, message: str) -> None:
    facts = facts_for_key(store, key)
    exact = [fact for fact in facts if fact.get("id") == fact_id]
    assert_true(len(exact) == 1 and len(facts) == 1, message)


def run_checks() -> subprocess.Popen[Any]:
    proc = start_daemon(reset_data=True)

    legacy = make_fact("p15_legacy_write_fact", "same-id")
    assert_true(one_req({"op": "write_fact", "fact": legacy}).get("ok") is True, "legacy first write_fact succeeds")
    assert_true(one_req({"op": "write_fact", "fact": legacy}).get("ok") is True, "legacy duplicate write_fact still succeeds")
    assert_true(store_size("p15_legacy_write_fact") == 2, "legacy write_fact duplicate append behavior is unchanged")

    first = make_fact("p15_once", "normal")
    first_resp = write_once(first)
    assert_true(first_resp.get("ok") is True, "write_fact_once first write succeeds")
    assert_true(first_resp.get("committed") is True, "first write reports committed=true")
    assert_true(first_resp.get("idempotent_replay") is False, "first write reports idempotent_replay=false")
    assert_single_fact(first["store"], first["key"], first["id"], "first write appended exactly one timeline fact")

    replay_resp = write_once(first)
    assert_true(replay_resp.get("ok") is True, "same fact retry succeeds")
    assert_true(replay_resp.get("idempotent_replay") is True, "same fact retry reports idempotent_replay=true")
    assert_single_fact(first["store"], first["key"], first["id"], "same fact retry did not append")

    conflict = conflict_variant(first)
    conflict_resp = write_once(conflict)
    assert_true(conflict_resp.get("ok") is False, "same id different value is rejected")
    assert_true(conflict_resp.get("error_code") == "duplicate_fact_id_conflict", "conflict has duplicate_fact_id_conflict code")
    assert_true(conflict_resp.get("committed") is False, "conflict reports committed=false")
    assert_true(conflict_resp.get("retryable") is False, "conflict reports retryable=false")
    assert_single_fact(first["store"], first["key"], first["id"], "conflict did not mutate timeline")

    cross_key_conflict = conflict_variant(first, key="other-key")
    cross_key_resp = write_once(cross_key_conflict)
    assert_true(cross_key_resp.get("error_code") == "duplicate_fact_id_conflict", "same store/id with different key conflicts")
    assert_true(store_size(first["store"]) == 1, "cross-key conflict did not append")

    timeout_fact = make_fact("p15_timeout_retry", "same-id")
    send_once_without_observing_ack(timeout_fact)
    retry_resp = write_once(timeout_fact)
    assert_true(retry_resp.get("ok") is True and retry_resp.get("committed") is True, "timeout/no-ack retry succeeds")
    assert_single_fact(timeout_fact["store"], timeout_fact["key"], timeout_fact["id"], "timeout/no-ack retry leaves one fact")

    concurrent = make_fact("p15_concurrent", "same-id")
    responses: list[dict[str, Any]] = []
    lock = threading.Lock()

    def attempt() -> None:
        resp = write_once(concurrent)
        with lock:
            responses.append(resp)

    threads = [threading.Thread(target=attempt, daemon=True) for _ in range(12)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    inserted = [resp for resp in responses if resp.get("ok") is True and resp.get("idempotent_replay") is False]
    replayed = [resp for resp in responses if resp.get("ok") is True and resp.get("idempotent_replay") is True]
    assert_true(len(inserted) == 1, "concurrent same fact has exactly one first commit")
    assert_true(len(replayed) == 11, "concurrent same fact retries replay")
    assert_single_fact(concurrent["store"], concurrent["key"], concurrent["id"], "concurrent retries append once")

    restart = make_fact("p15_restart", "same-id")
    assert_true(write_once(restart).get("idempotent_replay") is False, "restart fixture first write commits")
    assert_single_fact(restart["store"], restart["key"], restart["id"], "restart fixture has one fact before stop")
    return proc


def run_restart_check(proc: subprocess.Popen[Any]) -> subprocess.Popen[Any]:
    exit_code = stop_daemon(proc)
    assert_true(exit_code == 0, "daemon stopped cleanly before restart")
    proc = start_daemon(reset_data=False)
    restart_facts = facts_for_key("p15_restart", "same-id")
    assert_true(len(restart_facts) == 1, "restart replay restored one write-once fact")
    replay_resp = write_once(restart_facts[0])
    assert_true(replay_resp.get("idempotent_replay") is True, "post-restart same fact retry replays")
    assert_true(store_size("p15_restart") == 1, "post-restart retry did not append")
    return proc


def main() -> int:
    proc: subprocess.Popen[Any] | None = None
    try:
        proc = run_checks()
        proc = run_restart_check(proc)
        assert_true(one_req({"op": "ping"}).get("ok") is True, "daemon still accepts good requests")
    finally:
        if proc is not None:
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
    print("ALL IDEMPOTENT WRITE TESTS PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
