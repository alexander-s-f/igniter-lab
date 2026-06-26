#!/usr/bin/env python3
"""Verify LAB-TBACKEND-SERVER-CANONICAL-HASH-P4: the server is the authority for
fact content hashes.

The exact blake3/canonicalization correctness is pinned by the Rust unit tests
(`pure_core::tests::canonical_hash_*`). This e2e proves the server-authority
PROPERTIES over the live TCP wire, with no blake3 reimplementation in Python:

  * a tampered client value_hash never enters the ledger (it is replaced);
  * the stamped hash is client-independent (two different client hashes for the
    same value yield the same stored hash) and key-order independent;
  * distinct values get distinct hashes (content addressing);
  * strict mode (per-request `strict_hash` AND server `--hash-strict`) REJECTS a
    mismatched client hash with `value_hash_mismatch` and does not commit it;
  * write_fact_once replay/conflict is decided by the canonical hash, not the
    client-supplied one.
"""

from __future__ import annotations

import json
import os
import shutil
import signal
import socket
import struct
import subprocess
import time
import uuid
import zlib
from typing import Any


HOST = "127.0.0.1"
PORT = 7423
DATA_DIR = "canonical_hash_data"
LOG_PATH = "canonical_hash_daemon.log"
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
    body = json.dumps(req, separators=(",", ":")).encode("utf-8")
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


def make_fact(store: str, key: str, value: dict[str, Any], client_hash: str | None) -> dict[str, Any]:
    now = time.time()
    fact: dict[str, Any] = {
        "id": str(uuid.uuid4()),
        "store": store,
        "key": key,
        "value": value,
        "transaction_time": now,
        "valid_time": now,
        "schema_version": 1,
    }
    if client_hash is not None:
        fact["value_hash"] = client_hash
    return fact


def write_fact(fact: dict[str, Any], strict: bool | None = None) -> dict[str, Any]:
    req: dict[str, Any] = {"op": "write_fact", "fact": fact}
    if strict is not None:
        req["strict_hash"] = strict
    return one_req(req)


def write_once(fact: dict[str, Any], strict: bool | None = None) -> dict[str, Any]:
    req: dict[str, Any] = {"op": "write_fact_once", "fact": fact}
    if strict is not None:
        req["strict_hash"] = strict
    return one_req(req)


def facts_for_key(store: str, key: str) -> list[dict[str, Any]]:
    resp = one_req({"op": "facts_for", "store": store, "key": key})
    if resp.get("ok") is not True:
        raise RuntimeError(f"facts_for failed: {resp}")
    return resp.get("facts", [])


def stored_hash(store: str, fact_id: str, key: str) -> str | None:
    for f in facts_for_key(store, key):
        if f.get("id") == fact_id:
            return f.get("value_hash")
    return None


def store_size(store: str) -> int:
    resp = one_req({"op": "size", "store": store})
    return int(resp.get("size", -1)) if resp.get("ok") else -1


def start_daemon(hash_strict: bool, reset_data: bool = True) -> subprocess.Popen[Any]:
    if reset_data:
        shutil.rmtree(DATA_DIR, ignore_errors=True)
    try:
        os.remove(LOG_PATH)
    except FileNotFoundError:
        pass
    log = open(LOG_PATH, "wb")
    argv = [BINARY, "--host", HOST, "--port", str(PORT), "--data-dir", DATA_DIR, "--pool-size", "4"]
    if hash_strict:
        argv += ["--hash-strict", "true"]
    proc = subprocess.Popen(argv, stdout=log, stderr=log)
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


# ── Default (replace) policy ────────────────────────────────────────────────

def run_replace_checks() -> None:
    print("\n== default policy: replace (server overwrites client hash) ==")
    store = "p4_replace"
    value = {"state": "open", "amount": 10, "tags": ["b", "a"]}

    # A1: tampered client hash is accepted (replace mode) but does NOT survive.
    f1 = make_fact(store, "k1", value, client_hash="deadbeef-not-a-real-hash")
    r1 = write_fact(f1)
    assert_true(r1.get("ok") is True, "write_fact with wrong client hash is accepted (replace)")
    h1 = stored_hash(store, f1["id"], "k1")
    assert_true(h1 is not None and h1 != "deadbeef-not-a-real-hash",
                "tampered client hash did NOT enter the ledger (server replaced it)")

    # A2: a DIFFERENT wrong client hash for the SAME value → same stored hash.
    f2 = make_fact(store, "k2", value, client_hash="0000-different-wrong-hash")
    assert_true(write_fact(f2).get("ok") is True, "second write (same value, other wrong hash) accepted")
    h2 = stored_hash(store, f2["id"], "k2")
    assert_true(h1 == h2, "server hash is client-independent (same value → same stored hash)")

    # A3: omitting value_hash entirely also yields the same canonical hash.
    f3 = make_fact(store, "k3", value, client_hash=None)
    assert_true(write_fact(f3).get("ok") is True, "write_fact with NO value_hash accepted (serde default)")
    assert_true(stored_hash(store, f3["id"], "k3") == h1, "omitted hash → same server canonical hash")

    # A4: key-order independence (same logical value, reordered keys).
    reordered = {"tags": ["b", "a"], "amount": 10, "state": "open"}
    f4 = make_fact(store, "k4", reordered, client_hash=None)
    assert_true(write_fact(f4).get("ok") is True, "write_fact with reordered keys accepted")
    assert_true(stored_hash(store, f4["id"], "k4") == h1, "key order does not change the canonical hash")

    # A5: a DIFFERENT value → a DIFFERENT hash (content addressing).
    f5 = make_fact(store, "k5", {"state": "closed", "amount": 10, "tags": ["b", "a"]}, client_hash=None)
    assert_true(write_fact(f5).get("ok") is True, "write_fact of a different value accepted")
    assert_true(stored_hash(store, f5["id"], "k5") != h1, "different value → different canonical hash")

    # A6: array order IS significant (not sorted).
    f6 = make_fact(store, "k6", {"state": "open", "amount": 10, "tags": ["a", "b"]}, client_hash=None)
    assert_true(write_fact(f6).get("ok") is True, "write_fact with reordered array accepted")
    assert_true(stored_hash(store, f6["id"], "k6") != h1, "array element order changes the hash (order significant)")

    # A7: per-request strict + correct (canonical) hash → accepted.
    f7 = make_fact(store, "k7", value, client_hash=h1)
    assert_true(write_fact(f7, strict=True).get("ok") is True,
                "strict_hash=true with the correct canonical hash is accepted")

    # A8: per-request strict + wrong hash → REJECTED, not committed.
    before = store_size(store)
    f8 = make_fact(store, "k8", value, client_hash="totally-wrong")
    r8 = write_fact(f8, strict=True)
    assert_true(r8.get("ok") is False, "strict_hash=true with a wrong hash is rejected")
    assert_true(r8.get("error_code") == "value_hash_mismatch", "rejection carries error_code=value_hash_mismatch")
    assert_true(r8.get("committed") is False, "rejected write reports committed=false")
    assert_true(store_size(store) == before, "rejected write did NOT enter the ledger")
    assert_true(stored_hash(store, f8["id"], "k8") is None, "rejected fact id is absent from the timeline")


# ── write_fact_once decided by canonical hash ───────────────────────────────

def run_write_once_checks() -> None:
    print("\n== write_fact_once: replay/conflict decided by canonical hash ==")
    store = "p4_once"
    value = {"payload": "v", "n": 1}

    base = make_fact(store, "once-key", value, client_hash="wrong-hash-A")
    r1 = write_once(base)
    assert_true(r1.get("idempotent_replay") is False and r1.get("committed") is True,
                "first write_fact_once commits")

    # Same id + same value, but a DIFFERENT (wrong) client hash. Under the old
    # client-trusted logic this mismatched on value_hash and would CONFLICT;
    # canonical hashing makes it a clean Replay.
    retry = dict(base)
    retry["value_hash"] = "wrong-hash-B"
    r2 = write_once(retry)
    assert_true(r2.get("idempotent_replay") is True,
                "same id+value with a different client hash REPLAYS (canonical, not client, decides)")
    assert_true(len([f for f in facts_for_key(store, "once-key") if f.get("id") == base["id"]]) == 1,
                "replay did not append a duplicate")

    # Same id, DIFFERENT value → genuine conflict (canonical hashes differ).
    conflict = make_fact(store, "once-key", {"payload": "v2", "n": 1}, client_hash="wrong-hash-C")
    conflict["id"] = base["id"]
    r3 = write_once(conflict)
    assert_true(r3.get("error_code") == "duplicate_fact_id_conflict",
                "same id with a different value still conflicts (content differs)")


# ── Server-wide --hash-strict flag ──────────────────────────────────────────

def run_server_strict_checks() -> None:
    print("\n== server --hash-strict true: default-reject on mismatch ==")
    store = "p4_server_strict"
    value = {"state": "open"}

    # No per-request flag: the server default (strict) governs.
    bad = make_fact(store, "sk", value, client_hash="server-strict-wrong")
    r = write_fact(bad)
    assert_true(r.get("ok") is False and r.get("error_code") == "value_hash_mismatch",
                "with --hash-strict, a mismatched client hash is rejected by default")

    # A producer that omits the hash entirely is fine (asserts nothing).
    ok_fact = make_fact(store, "sk2", value, client_hash=None)
    assert_true(write_fact(ok_fact).get("ok") is True,
                "with --hash-strict, omitting value_hash is still accepted (no false assertion)")

    # A per-request override can RELAX strictness for one write.
    relaxed = make_fact(store, "sk3", value, client_hash="still-wrong")
    assert_true(write_fact(relaxed, strict=False).get("ok") is True,
                "per-request strict_hash=false relaxes the server default for one write")


def main() -> int:
    proc: subprocess.Popen[Any] | None = None
    try:
        proc = start_daemon(hash_strict=False, reset_data=True)
        run_replace_checks()
        run_write_once_checks()
        stop_daemon(proc)
        proc = start_daemon(hash_strict=True, reset_data=True)
        run_server_strict_checks()
    finally:
        if proc is not None:
            code = stop_daemon(proc)
            assert_true(code == 0, "daemon stopped cleanly")
        shutil.rmtree(DATA_DIR, ignore_errors=True)
        try:
            os.remove(LOG_PATH)
        except FileNotFoundError:
            pass

    if FAILED:
        print(f"\nFAILURES: {FAILED}")
        return 1
    print("\nALL CANONICAL HASH TESTS PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
