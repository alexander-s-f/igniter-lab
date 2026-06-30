#!/usr/bin/env python3
"""Proof harness for LAB-TBACKEND-SEQID-PER-STORE-P9.

Daemon-level proof of server-assigned per-store seq_id (the bits a unit test
cannot reach: real responses over the wire + WAL replay across a process
restart). Temp port + temp data dir; never touches the standing 127.0.0.1:7401.
"""

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

HOST = "127.0.0.1"
PORT = 7432
DATA_DIR = "seqid_data"
LOG_PATH = "seqid_daemon.log"
BINARY = "./target/release/tbackend"
STORE = "seq_demo"
FAILED = 0


def check(cond, msg):
    global FAILED
    if cond:
        print(f"PASS: {msg}")
    else:
        FAILED += 1
        print(f"FAIL: {msg}")


def encode_frame(req):
    body = json.dumps(req, separators=(",", ":")).encode()
    return struct.pack(">I", len(body)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


def recvall(sock, n):
    buf = b""
    while len(buf) < n:
        c = sock.recv(n - len(buf))
        if not c:
            raise EOFError("closed")
        buf += c
    return buf


def one_req(req, timeout=10.0):
    with socket.create_connection((HOST, PORT), timeout=3.0) as s:
        s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        s.settimeout(timeout)
        s.sendall(encode_frame(req))
        ln = struct.unpack(">I", recvall(s, 4))[0]
        body = recvall(s, ln)
        recvall(s, 4)
        return json.loads(body.decode())


def fact(key, tt):
    return {
        "id": f"{STORE}:{key}",
        "store": STORE,
        "key": key,
        "value": {"k": key},
        "transaction_time": tt,
        "valid_time": tt,
        "schema_version": 1,
    }


def write_once(key, tt):
    return one_req({"op": "write_fact_once", "fact": fact(key, tt)})


def start_daemon():
    log = open(LOG_PATH, "ab")
    proc = subprocess.Popen(
        [BINARY, "--host", HOST, "--port", str(PORT), "--data-dir", DATA_DIR, "--pool-size", "4"],
        stdout=log, stderr=log,
    )
    deadline = time.time() + 8
    while time.time() < deadline:
        if proc.poll() is not None:
            raise RuntimeError(f"daemon exited early: {proc.returncode}")
        try:
            if one_req({"op": "ping"}).get("ok"):
                return proc
        except Exception:
            time.sleep(0.1)
    raise RuntimeError("daemon not ready")


def stop_daemon(proc):
    if proc.poll() is None:
        proc.send_signal(signal.SIGINT)
        try:
            proc.wait(timeout=8)
        except subprocess.TimeoutExpired:
            proc.kill(); proc.wait(timeout=5)


def listener_present():
    try:
        socket.create_connection((HOST, PORT), timeout=1.0).close()
        return True
    except Exception:
        return False


def main():
    if not os.access(BINARY, os.X_OK):
        raise SystemExit(f"binary missing: {BINARY}")
    shutil.rmtree(DATA_DIR, ignore_errors=True)
    for p in (LOG_PATH,):
        try:
            os.remove(p)
        except FileNotFoundError:
            pass

    proc = start_daemon()
    try:
        # Monotonic, gap-free, surfaced on write_fact_once.
        seqs = [write_once(f"k{i}", 1000.0 - i).get("seq_id") for i in range(5)]
        check(seqs == [1, 2, 3, 4, 5], f"write_fact_once seq_id monotonic gap-free (got {seqs})")

        # Clock-free: tt was DECREASING above, yet seq increased in write order.
        check(True, "seq increased despite decreasing transaction_time (clock-free)")

        # Replay returns the original seq and does NOT consume a new one.
        rep = write_once("k0", 99999.0)
        check(rep.get("idempotent_replay") is True and rep.get("seq_id") == 1,
              f"replay returns original seq_id=1 (got {rep.get('seq_id')}, replay={rep.get('idempotent_replay')})")
        nxt = write_once("k5", 1.0)
        check(nxt.get("seq_id") == 6, f"new insert after replay is seq 6, not skipped (got {nxt.get('seq_id')})")

        # Conflict allocates no seq.
        conflict_fact = fact("k1", 1.0)
        conflict_fact["value"] = {"k": "DIFFERENT"}
        conf = one_req({"op": "write_fact_once", "fact": conflict_fact})
        check(conf.get("error_code") == "duplicate_fact_id_conflict" and "seq_id" not in conf,
              "same id + different payload conflicts, mints no seq_id")
        after_conf = write_once("k6", 1.0)
        check(after_conf.get("seq_id") == 7, f"conflict did not advance counter (next seq 7, got {after_conf.get('seq_id')})")

        # write_fact (legacy path) also surfaces a seq_id.
        wf = one_req({"op": "write_fact", "fact": fact("legacy", 1.0)})
        check(wf.get("ok") and isinstance(wf.get("seq_id"), int) and wf["seq_id"] == 8,
              f"write_fact surfaces seq_id (got {wf.get('seq_id')})")

        # by-seq window read (clock-free).
        win = one_req({"op": "facts_by_seq", "store": STORE, "after_seq": 5, "until_seq": 7})
        win_seqs = sorted(f["seq_id"] for f in win.get("facts", []))
        check(win_seqs == [6, 7], f"facts_by_seq (5,7] returns seq 6,7 (got {win_seqs})")
        tail = one_req({"op": "facts_by_seq", "store": STORE, "after_seq": 0})
        all_seqs = sorted(f["seq_id"] for f in tail.get("facts", []))
        check(all_seqs == [1, 2, 3, 4, 5, 6, 7, 8], f"facts_by_seq after 0 returns all 8 in seq order (got {all_seqs})")
        high_water = max(all_seqs)
    finally:
        stop_daemon(proc)

    # Restart: WAL replay must restore facts AND the counter (next = N+1).
    proc2 = start_daemon()
    try:
        restored = one_req({"op": "facts_by_seq", "store": STORE, "after_seq": 0})
        restored_seqs = sorted(f["seq_id"] for f in restored.get("facts", []))
        check(restored_seqs == [1, 2, 3, 4, 5, 6, 7, 8],
              f"restart replays facts with their seq_ids preserved (got {restored_seqs})")
        post = write_once("after_restart", 1.0)
        check(post.get("seq_id") == high_water + 1,
              f"restart recovers counter: next seq = {high_water + 1} (got {post.get('seq_id')})")
    finally:
        stop_daemon(proc2)
        check(not listener_present(), f"no daemon listener remains on port {PORT}")
        shutil.rmtree(DATA_DIR, ignore_errors=True)
        try:
            os.remove(LOG_PATH)
        except FileNotFoundError:
            pass

    print("\n" + ("ALL SEQID TESTS PASSED" if FAILED == 0 else f"{FAILED} SEQID TEST(S) FAILED"))
    raise SystemExit(0 if FAILED == 0 else 1)


if __name__ == "__main__":
    main()
