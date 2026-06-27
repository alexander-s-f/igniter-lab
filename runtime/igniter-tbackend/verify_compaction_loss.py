#!/usr/bin/env python3
"""Proof harness for LAB-TBACKEND-SAFE-COMPACTION-STOP-THE-WORLD-P12.

After P12, compaction has a SAFE manual mode. This proves it on temporary
loopback daemons (temp port + temp data dir; the standing 127.0.0.1:7401 is never
touched):

  Phase 1 (gate):     default daemon refuses snapshot_trigger (compaction_disabled);
                      the removed --unsafe-compaction flag does NOT enable it.
  Phase 2 (no loss):  with --enable-compaction true, writes issued concurrently
                      with a compaction are NOT lost (the stop-the-world gate; the
                      B3 fix — vs the pre-P12 19/28 loss), file+dir fsyncs ran
                      (durable rename, B4), retained facts keep their seq_id and a
                      new insert continues the sequence (B5), canonical hash kept.
  Phase 3 (busy):     a second concurrent trigger gets compaction_in_progress.
  Phase 4 (crash):    SIGKILL after a compaction; restart replays the compacted
                      store with no loss and seqs intact.
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
PORT = 7431
DATA_DIR = "compaction_safe_data"
LOG_PATH = "compaction_safe_daemon.log"
BINARY = "./target/release/tbackend"
STORE = "ledger_safe"
TARGET_STORE = "ledger_safe_rollup"

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
    chunks, remaining = [], size
    while remaining > 0:
        chunk = sock.recv(remaining)
        if not chunk:
            raise EOFError("socket closed")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def one_req(req, timeout=30.0):
    with socket.create_connection((HOST, PORT), timeout=5.0) as sock:
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


def make_fact(key, tt, payload):
    value = {"payload": payload, "key": key}
    return {
        "id": str(uuid.uuid4()),
        "store": STORE,
        "key": key,
        "value": value,
        "value_hash": value_hash(value),
        "transaction_time": tt,
        "valid_time": tt,
        "schema_version": 1,
    }


def write_fact(fact):
    return one_req({"op": "write_fact", "fact": fact})


def store_size():
    resp = one_req({"op": "size", "store": STORE})
    return int(resp.get("size", -1)) if resp.get("ok") else -1


def facts_for_key(key):
    resp = one_req({"op": "facts_for", "store": STORE, "key": key})
    return resp.get("facts", []) if resp.get("ok") else []


def all_facts_by_seq():
    resp = one_req({"op": "facts_by_seq", "store": STORE, "after_seq": 0})
    return resp.get("facts", []) if resp.get("ok") else []


def compaction_stats():
    return one_req({"op": "__compaction_stats"})


def start_daemon(enable_compaction=False, unsafe_compaction=False, wipe=True):
    if wipe:
        shutil.rmtree(DATA_DIR, ignore_errors=True)
        try:
            os.remove(LOG_PATH)
        except FileNotFoundError:
            pass
    log = open(LOG_PATH, "ab")
    args = [BINARY, "--host", HOST, "--port", str(PORT), "--data-dir", DATA_DIR, "--pool-size", "8"]
    if enable_compaction:
        args += ["--enable-compaction", "true"]
    if unsafe_compaction:
        args += ["--unsafe-compaction", "true"]
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


def stop_daemon(proc, kill=False):
    if proc.poll() is None:
        if kill:
            proc.kill()
        else:
            proc.send_signal(signal.SIGINT)
        try:
            proc.wait(timeout=8)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)


def create_policy():
    resp = one_req({
        "op": "snapshot_policy_create",
        "source_store": STORE,
        "target_store": TARGET_STORE,
        "retention_period": 3600.0,
        "group_by": [],
        "aggregates": [{"op": "count", "field": ""}],
    })
    if not resp.get("ok"):
        raise RuntimeError(f"policy create failed: {resp}")
    return resp["policy_id"]


def seed_warm(n, now):
    """Bulk-seed n warm facts on one persistent socket; returns acked count."""
    acked = 0
    with socket.create_connection((HOST, PORT), timeout=5.0) as sock:
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        sock.settimeout(20.0)
        for i in range(n):
            f = make_fact(f"warm:{i}", now, "warm")
            sock.sendall(encode_frame({"op": "write_fact", "fact": f}))
            length = struct.unpack(">I", recvall(sock, 4))[0]
            resp = json.loads(recvall(sock, length).decode("utf-8"))
            recvall(sock, 4)
            if resp.get("ok"):
                acked += 1
    return acked


def listener_present():
    try:
        socket.create_connection((HOST, PORT), timeout=1.0).close()
        return True
    except Exception:
        return False


# ── Phase 1: gate ────────────────────────────────────────────────────────────

def phase_gate():
    print("\n== Phase 1: gate — disabled by default; --unsafe-compaction does not enable ==")
    proc = start_daemon(enable_compaction=False, unsafe_compaction=True)
    try:
        now = time.time()
        write_fact(make_fact("warm:1", now, "p"))
        write_fact(make_fact("cold:1", now - 100000.0, "p"))
        policy_id = create_policy()
        resp = one_req({"op": "snapshot_trigger", "policy_id": policy_id})
        check(resp.get("ok") is False, f"snapshot_trigger refused (ok={resp.get('ok')})")
        check(resp.get("error_code") == "compaction_disabled",
              f"refusal carries compaction_disabled (got {resp.get('error_code')})")
        size_before = store_size()
        time.sleep(6.0)
        check(store_size() == size_before,
              f"no background sweep ran in 6s (size stable at {size_before})")
    finally:
        stop_daemon(proc)


# ── Phase 2: safe compaction loses nothing + durable + seq-preserving ─────────

def phase_safe():
    print("\n== Phase 2: --enable-compaction true — zero loss + durable rename + seq continuity ==")
    proc = start_daemon(enable_compaction=True)
    try:
        now = time.time()
        write_fact(make_fact("cold:1", now - 100000.0, "cold"))  # 1 cold -> swap happens
        warm_seed = 40000
        print(f"  seeding {warm_seed} warm facts (widens the compaction window)...")
        seed_warm(warm_seed, now)

        # hash of a known warm fact BEFORE compaction (server canonical hash)
        pre = facts_for_key("warm:0")
        pre_hash = pre[0]["value_hash"] if pre else None

        policy_id = create_policy()
        stats0 = compaction_stats()

        # Fire canaries from several threads WHILE compaction runs. With the
        # stop-the-world gate they block then land on the new engine — none lost.
        done = threading.Event()
        lock = threading.Lock()
        acked = []

        def canary_writer(tid):
            i = 0
            while not done.is_set():
                key = f"canary:{tid}:{i}"
                if write_fact(make_fact(key, time.time(), "canary")).get("ok"):
                    with lock:
                        acked.append(key)
                i += 1

        writers = [threading.Thread(target=canary_writer, args=(t,)) for t in range(4)]
        for w in writers:
            w.start()
        trig = one_req({"op": "snapshot_trigger", "policy_id": policy_id})
        done.set()
        for w in writers:
            w.join()

        check(trig.get("ok") is True, f"compaction succeeded (resp ok={trig.get('ok')})")
        check(trig.get("durable_rename") is True, "response reports durable_rename=true")

        lost = [k for k in acked if not facts_for_key(k)]
        print(f"  acked {len(acked)} concurrent canaries during compaction; lost {len(lost)}")
        check(len(acked) > 0, "canary writes were acked concurrently with compaction")
        check(len(lost) == 0, f"ZERO acknowledged writes lost (lost={len(lost)})")

        # Durable rename: file + dir fsync both ran.
        stats1 = compaction_stats()
        check(stats1["file_fsyncs"] > stats0["file_fsyncs"], "temp-WAL file fsync executed")
        check(stats1["dir_fsyncs"] > stats0["dir_fsyncs"], "directory fsync executed (rename durable)")

        # Canonical hash preserved across compaction.
        post = facts_for_key("warm:0")
        post_hash = post[0]["value_hash"] if post else None
        check(pre_hash is not None and pre_hash == post_hash,
              "retained fact keeps its canonical value_hash across compaction")

        # Seq continuity: retained facts keep seqs; a new insert never reuses one.
        facts = all_facts_by_seq()
        seqs = sorted(f["seq_id"] for f in facts)
        max_seq = seqs[-1] if seqs else 0
        check(len(seqs) == len(set(seqs)), "all retained seq_ids are unique (no collision)")
        check(all(s > 0 for s in seqs), "all retained facts carry a real (non-zero) seq_id")
        nr = write_fact(make_fact("post-compaction:1", time.time(), "after"))
        new_seq = nr.get("seq_id", 0)
        check(new_seq > max_seq,
              f"post-compaction insert continues the sequence (new {new_seq} > max retained {max_seq})")
    finally:
        stop_daemon(proc)


# ── Phase 3: busy refusal ─────────────────────────────────────────────────────

def phase_busy():
    print("\n== Phase 3: concurrent trigger returns compaction_in_progress ==")
    proc = start_daemon(enable_compaction=True)
    try:
        now = time.time()
        write_fact(make_fact("cold:1", now - 100000.0, "cold"))
        seed_warm(40000, now)
        policy_id = create_policy()

        results = {}

        def trig(name):
            results[name] = one_req({"op": "snapshot_trigger", "policy_id": policy_id})

        a = threading.Thread(target=trig, args=("a",))
        b = threading.Thread(target=trig, args=("b",))
        a.start()
        time.sleep(0.02)  # let A win the CAS and start the slow build
        b.start()
        a.join()
        b.join()

        codes = {results["a"].get("error_code"), results["b"].get("error_code")}
        oks = [r.get("ok") for r in results.values()]
        check(True in oks, "one trigger completed ok")
        check("compaction_in_progress" in codes,
              f"the other got compaction_in_progress (codes={codes})")
    finally:
        stop_daemon(proc)


# ── Phase 4: process-crash durability of the rename ───────────────────────────

def phase_crash():
    print("\n== Phase 4: SIGKILL after compaction; restart replays the compacted store ==")
    proc = start_daemon(enable_compaction=True)
    crashed = False
    try:
        now = time.time()
        write_fact(make_fact("cold:1", now - 100000.0, "cold"))
        warm = 5000
        seed_warm(warm, now)
        policy_id = create_policy()
        trig = one_req({"op": "snapshot_trigger", "policy_id": policy_id})
        check(trig.get("ok") is True, "compaction ran before crash")
        size_pre = store_size()
        seqs_pre = sorted(f["seq_id"] for f in all_facts_by_seq())
        # Hard process crash (no graceful flush) AFTER the durable compaction.
        stop_daemon(proc, kill=True)
        crashed = True
    finally:
        if not crashed:
            stop_daemon(proc)

    proc2 = start_daemon(enable_compaction=True, wipe=False)  # reuse the data dir
    try:
        check(store_size() == size_pre,
              f"compacted store replays after crash (size {store_size()} == {size_pre})")
        seqs_post = sorted(f["seq_id"] for f in all_facts_by_seq())
        check(seqs_post == seqs_pre, "seq_ids survive the crash unchanged")
    finally:
        stop_daemon(proc2)


def main():
    if not os.access(BINARY, os.X_OK):
        raise SystemExit(f"daemon binary not found/executable at {BINARY}")
    try:
        phase_gate()
        phase_safe()
        phase_busy()
        phase_crash()
    finally:
        check(not listener_present(), f"no daemon listener remains on port {PORT}")
        shutil.rmtree(DATA_DIR, ignore_errors=True)
        try:
            os.remove(LOG_PATH)
        except FileNotFoundError:
            pass

    print("\n" + ("ALL SAFE COMPACTION TESTS PASSED" if FAILED == 0
                  else f"{FAILED} SAFE COMPACTION TEST(S) FAILED"))
    raise SystemExit(0 if FAILED == 0 else 1)


if __name__ == "__main__":
    main()
