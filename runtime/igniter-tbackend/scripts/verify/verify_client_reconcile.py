#!/usr/bin/env python3
"""Verify P14 client-side reconcile semantics for timeout-unknown writes."""

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
PORT = 7420
DATA_DIR = "client_reconcile_data"
LOG_PATH = "client_reconcile_daemon.log"
BINARY = "./target/release/tbackend"
FAILED = 0

COMMITTED_ACKED = "committed_acked"
REJECTED_BEFORE_COMMIT = "rejected_before_commit"
COMMITTED_AFTER_TIMEOUT = "committed_after_timeout"
NOT_OBSERVED_AFTER_TIMEOUT = "not_observed_after_timeout"
CONFLICT = "conflict"
UNKNOWN = "unknown"


class ReconcileReadDeferred(Exception):
    pass


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


def make_fact(store: str, key: str, payload: str = "p14") -> dict[str, Any]:
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


def classify_write_response(resp: dict[str, Any] | None) -> str:
    if resp is None:
        return UNKNOWN
    if resp.get("ok") is True:
        return COMMITTED_ACKED
    if resp.get("error_code") == "overloaded" and resp.get("committed") is False:
        return REJECTED_BEFORE_COMMIT
    return UNKNOWN


def facts_for_key(store: str, key: str) -> list[dict[str, Any]]:
    resp = one_req({"op": "facts_for", "store": store, "key": key})
    if resp.get("error_code") == "overloaded" and resp.get("committed") is False:
        raise ReconcileReadDeferred("read-back was rejected before commit")
    if resp.get("ok") is not True:
        raise RuntimeError(f"facts_for failed: {resp}")
    return resp.get("facts", [])


def reconcile_after_timeout(fact: dict[str, Any], deadline_sec: float = 2.0) -> str:
    deadline = time.time() + deadline_sec
    saw_conflict = False
    while time.time() < deadline:
        try:
            facts = facts_for_key(fact["store"], fact["key"])
        except ReconcileReadDeferred:
            time.sleep(0.05)
            continue
        for observed in facts:
            if observed.get("id") != fact["id"]:
                continue
            # LAB-TBACKEND-SERVER-CANONICAL-HASH-P4: value_hash is server-
            # stamped canonical blake3, so reconcile by the client-visible
            # logical payload rather than the legacy client-supplied hash.
            if observed.get("value") == fact["value"]:
                return COMMITTED_AFTER_TIMEOUT
            saw_conflict = True
        if saw_conflict:
            return CONFLICT
        time.sleep(0.05)
    return NOT_OBSERVED_AFTER_TIMEOUT


def send_without_observing_ack(req: dict[str, Any]) -> None:
    with socket.create_connection((HOST, PORT), timeout=3.0) as sock:
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        sock.sendall(encode_frame(req))
        # The client deadline expires before any ack is read. From the client's
        # perspective this is a timeout/unknown outcome; reconcile must decide.
        deadline_expired_at = time.time() + 0.001
        while time.time() < deadline_expired_at:
            pass
        # Keep the socket alive briefly so this test is about an unobserved ack,
        # not a race where the server never receives the full request frame.
        time.sleep(0.05)


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


def preseed_large_store() -> None:
    payload = "x" * 65536
    with socket.create_connection((HOST, PORT), timeout=3.0) as sock:
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        for i in range(512):
            fact = make_fact("p14_big", f"k-{i}", payload)
            resp = send_req(sock, {"op": "write_fact", "fact": fact}, timeout=10.0)
            if resp.get("ok") is not True:
                raise RuntimeError(f"preseed failed at {i}: {resp}")


def hold_one_inflight_request() -> socket.socket:
    sock = socket.create_connection((HOST, PORT), timeout=3.0)
    sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1024)
    sock.sendall(encode_frame({"op": "facts_for", "store": "p14_big"}))
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
            fact = make_fact("p14_overload_probe", key)
            try:
                resp = one_req({"op": "write_fact", "fact": fact}, timeout=3.0)
            except BaseException:
                idx += 1
                continue
            if classify_write_response(resp) == REJECTED_BEFORE_COMMIT:
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
        acked = make_fact("p14_committed_acked", "normal")
        acked_resp = one_req({"op": "write_fact", "fact": acked})
        assert_true(classify_write_response(acked_resp) == COMMITTED_ACKED, "ok=true classifies committed_acked")

        timeout_fact = make_fact("p14_timeout_unknown", "sent-no-ack")
        send_without_observing_ack({"op": "write_fact", "fact": timeout_fact})
        timeout_status = reconcile_after_timeout(timeout_fact)
        assert_true(timeout_status == COMMITTED_AFTER_TIMEOUT, "exact id/value scan finds committed_after_timeout")

        missing = make_fact("p14_timeout_unknown", "never-sent")
        missing_status = reconcile_after_timeout(missing, deadline_sec=0.2)
        assert_true(
            missing_status == NOT_OBSERVED_AFTER_TIMEOUT,
            "not observed before deadline stays not_observed_after_timeout",
        )

        conflict_expected = make_fact("p14_conflict", "same-id-different-hash", "expected")
        conflict_observed = dict(conflict_expected)
        conflict_observed["value"] = {"payload": "different", "key": conflict_expected["key"]}
        conflict_observed["value_hash"] = value_hash(conflict_observed["value"])
        assert_true(one_req({"op": "write_fact", "fact": conflict_observed}).get("ok") is True, "conflict fixture writes")
        assert_true(reconcile_after_timeout(conflict_expected) == CONFLICT, "same id with different value_hash classifies conflict")

        duplicate = make_fact("p14_duplicate_retry", "same-id")
        assert_true(one_req({"op": "write_fact", "fact": duplicate}).get("ok") is True, "first retry fixture write succeeds")
        assert_true(one_req({"op": "write_fact", "fact": duplicate}).get("ok") is True, "blind same-id retry is accepted")
        dup_size = one_req({"op": "size", "store": "p14_duplicate_retry"})
        assert_true(dup_size.get("size") == 2, "blind retry appends duplicate timeline fact")

        preseed_large_store()
        blocker = hold_one_inflight_request()
        try:
            rejected = force_overload()
        finally:
            blocker.close()
        assert_true(bool(rejected), "overload rejection can be forced")
        if rejected:
            assert_true(
                classify_write_response(rejected["resp"]) == REJECTED_BEFORE_COMMIT,
                "overloaded committed=false classifies rejected_before_commit",
            )
            rejected_status = reconcile_after_timeout(rejected["fact"], deadline_sec=1.0)
            assert_true(
                rejected_status == NOT_OBSERVED_AFTER_TIMEOUT,
                "rejected_before_commit write is not present in timeline",
            )

        metrics = one_req({"op": "metrics"})
        assert_true(metrics.get("overload_rejections", 0) >= 1, "metrics expose overload_rejections")
        assert_true(one_req({"op": "ping"}).get("ok") is True, "daemon still accepts good requests")
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
    print("ALL CLIENT RECONCILE TESTS PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
