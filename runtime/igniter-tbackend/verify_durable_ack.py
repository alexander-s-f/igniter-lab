#!/usr/bin/env python3
"""Proof harness for LAB-TBACKEND-DURABLE-ACK-GROUP-COMMIT-P6.

Covers the software-testable acceptance tests (test 8, real power-loss, is a
manually gated hardware proof, not run here):

  1. accepted survives PROCESS crash (SIGKILL, no graceful flush) + restart.
  2. a `durable` ack waits for an fdatasync (sync_count seam proves the syscall ran).
  3. K concurrent durable writes coalesce into < K fdatasyncs (group commit).
  4. latency: accepted returns without an fsync wait; durable returns ~ within the window.
  5. ephemeral (data_dir=None) cannot return durable — downgrades to in_memory.
  6. injected fdatasync failure -> ok:false, committed:false, retryable:true (no silent downgrade).

Temp loopback only (port 7432 + temp data dir); never touches 127.0.0.1:7401.
"""

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

HOST = "127.0.0.1"
PORT = 7432
DATA_DIR = "durable_ack_data"
LOG_PATH = "durable_ack_daemon.log"
BINARY = "./target/release/tbackend"
STORE = "durable_demo"

FAILED = 0


def check(cond, msg):
    global FAILED
    if cond:
        print(f"PASS: {msg}")
    else:
        FAILED += 1
        print(f"FAIL: {msg}")


def encode_frame(req):
    body = json.dumps(req, separators=(",", ":")).encode("utf-8")
    return struct.pack(">I", len(body)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


def recvall(sock, size):
    chunks = []
    remaining = size
    while remaining > 0:
        chunk = sock.recv(remaining)
        if not chunk:
            raise EOFError("socket closed")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def one_req(req, timeout=10.0):
    with socket.create_connection((HOST, PORT), timeout=3.0) as sock:
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        sock.settimeout(timeout)
        sock.sendall(encode_frame(req))
        length = struct.unpack(">I", recvall(sock, 4))[0]
        body = recvall(sock, length)
        recvall(sock, 4)
        return json.loads(body.decode("utf-8"))


def value_hash(value):
    body = json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return str(zlib.crc32(body) & 0xFFFFFFFF)


def make_fact(key, payload="p"):
    now = time.time()
    value = {"payload": payload, "key": key}
    return {
        "id": f"{STORE}:{key}",
        "store": STORE,
        "key": key,
        "value": value,
        "value_hash": value_hash(value),
        "transaction_time": now,
        "valid_time": now,
        "schema_version": 1,
    }


def write_once(key, durability=None, payload="p"):
    req = {"op": "write_fact_once", "fact": make_fact(key, payload)}
    if durability is not None:
        req["durability"] = durability
    return one_req(req)


def stats():
    return one_req({"op": "__durability_stats", "store": STORE})


def present(key):
    resp = one_req({"op": "facts_for", "store": STORE, "key": key})
    return resp.get("ok") and len(resp.get("facts", [])) > 0


def start_daemon(data_dir=DATA_DIR, extra_args=None, clean=True):
    if clean and data_dir:
        shutil.rmtree(data_dir, ignore_errors=True)
    log = open(LOG_PATH, "ab")
    args = [BINARY, "--host", HOST, "--port", str(PORT), "--pool-size", "8"]
    args += ["--data-dir", data_dir if data_dir else "nil"]
    if extra_args:
        args += extra_args
    proc = subprocess.Popen(args, stdout=log, stderr=log)
    deadline = time.time() + 8
    while time.time() < deadline:
        if proc.poll() is not None:
            raise RuntimeError(f"daemon exited early: {proc.returncode}")
        try:
            if one_req({"op": "ping"}).get("ok"):
                return proc
        except Exception:
            time.sleep(0.1)
    raise RuntimeError("daemon did not become ready")


def stop_daemon(proc, sigkill=False):
    if proc.poll() is None:
        proc.send_signal(signal.SIGKILL if sigkill else signal.SIGINT)
        try:
            proc.wait(timeout=8)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)


def listener_present():
    try:
        socket.create_connection((HOST, PORT), timeout=1.0).close()
        return True
    except Exception:
        return False


# ── Test 1: accepted survives process crash (SIGKILL) ────────────────────────

def test_accepted_crash_survival():
    print("\n== Test 1: accepted ack survives SIGKILL process crash + restart ==")
    proc = start_daemon()
    try:
        resp = write_once("crash:1", durability="accepted")
        check(resp.get("ok") and resp.get("durability") == "accepted",
              f"accepted write acked (durability={resp.get('durability')})")
    finally:
        stop_daemon(proc, sigkill=True)  # hard kill: no graceful flush_pure
    # restart same data dir, no clean
    proc = start_daemon(clean=False)
    try:
        check(present("crash:1"),
              "accepted fact replayed from WAL after SIGKILL (page-cache survived process death)")
    finally:
        stop_daemon(proc)


# ── Tests 2-4,6: durable path on a group-commit daemon ───────────────────────

def test_durable_path():
    print("\n== Tests 2/3/4/6: durable group-commit fdatasync ==")
    proc = start_daemon(extra_args=["--commit-interval-ms", "50", "--commit-max-batch", "256"])
    try:
        # Test 2: fdatasync executed before a durable ack.
        before = stats()["sync_count"]
        resp = write_once("dur:1", durability="durable")
        after = stats()["sync_count"]
        check(resp.get("ok") and resp.get("durability") == "durable",
              f"durable write acked durable (durability={resp.get('durability')})")
        check(after > before, f"fdatasync executed before durable ack (sync_count {before}->{after})")
        check(present("dur:1"), "durable fact present")

        # Test 4: latency contract — accepted returns without an fsync wait.
        t0 = time.time()
        write_once("acc:lat", durability="accepted")
        acc_ms = (time.time() - t0) * 1000
        t0 = time.time()
        write_once("dur:lat", durability="durable")
        dur_ms = (time.time() - t0) * 1000
        check(acc_ms < 30, f"accepted ack fast, no fsync wait ({acc_ms:.1f}ms)")
        check(dur_ms < 600, f"durable ack returns within window+fsync ({dur_ms:.1f}ms)")
        print(f"  latency: accepted={acc_ms:.1f}ms durable={dur_ms:.1f}ms")

        # Test 3: K concurrent durable writes coalesce into < K fdatasyncs.
        before = stats()["sync_count"]
        K = 24
        acked = []
        lock = threading.Lock()

        def durable_writer(n):
            r = write_once(f"batch:{n}", durability="durable")
            with lock:
                acked.append(r.get("ok") and r.get("durability") == "durable")

        threads = [threading.Thread(target=durable_writer, args=(n,)) for n in range(K)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        after = stats()["sync_count"]
        syncs = after - before
        check(all(acked) and len(acked) == K, f"all {K} concurrent durable writes acked durable")
        check(syncs < K, f"{K} concurrent durable writes coalesced into {syncs} fdatasyncs (< {K})")
        check(all(present(f"batch:{n}") for n in range(K)), "all batched durable facts present")
        print(f"  group commit: {K} durable writes -> {syncs} fdatasyncs")

        # Test 6: injected fdatasync failure -> committed:false, retryable:true.
        one_req({"op": "__durability_fault", "store": STORE, "armed": True})
        resp = write_once("fault:1", durability="durable")
        check(resp.get("ok") is False and resp.get("committed") is False and resp.get("retryable") is True,
              f"injected sync failure fails the ack (ok={resp.get('ok')}, committed={resp.get('committed')}, "
              f"retryable={resp.get('retryable')})")
        check(resp.get("durability") != "durable", "failed durable write is NOT reported durable (no silent downgrade)")
        # disarm and confirm recovery: same fact retried becomes durable replay.
        one_req({"op": "__durability_fault", "store": STORE, "armed": False})
        resp = write_once("fault:1", durability="durable")
        check(resp.get("ok") and resp.get("durability") == "durable",
              f"after disarm, retry of same fact is durable (durability={resp.get('durability')})")
    finally:
        stop_daemon(proc)


# ── Test 5: ephemeral cannot return durable ──────────────────────────────────

def test_ephemeral_honesty():
    print("\n== Test 5: ephemeral (data_dir=None) cannot falsely return durable ==")
    proc = start_daemon(data_dir=None)
    try:
        resp = write_once("eph:1", durability="durable")
        check(resp.get("durability") == "in_memory",
              f"ephemeral durable downgraded to in_memory (durability={resp.get('durability')})")
        check(resp.get("durability") != "durable", "ephemeral never reports durable")
        st = stats()
        check(st.get("durable_capable") is False, "stats report durable_capable=false in ephemeral mode")
    finally:
        stop_daemon(proc)


def main():
    if not os.access(BINARY, os.X_OK):
        raise SystemExit(f"daemon binary not found/executable at {BINARY}")
    try:
        os.remove(LOG_PATH)
    except FileNotFoundError:
        pass
    try:
        test_accepted_crash_survival()
        test_durable_path()
        test_ephemeral_honesty()
    finally:
        check(not listener_present(), f"no daemon listener remains on port {PORT}")
        shutil.rmtree(DATA_DIR, ignore_errors=True)
        try:
            os.remove(LOG_PATH)
        except FileNotFoundError:
            pass

    print("\n" + ("ALL DURABLE ACK TESTS PASSED" if FAILED == 0 else f"{FAILED} DURABLE ACK TEST(S) FAILED"))
    raise SystemExit(0 if FAILED == 0 else 1)


if __name__ == "__main__":
    main()
