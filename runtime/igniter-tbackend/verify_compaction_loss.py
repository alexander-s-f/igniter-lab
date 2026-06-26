#!/usr/bin/env python3
"""Proof harness for LAB-TBACKEND-COMPACTION-SAFETY-GATE-P6.

Two phases, each on a temporary loopback daemon (temp port + temp data dir):

  Phase 1 (gate):  default daemon (no --unsafe-compaction) must REFUSE
                   snapshot_trigger with error_code=compaction_disabled_unsafe.

  Phase 2 (B3):    daemon started with --unsafe-compaction true reproduces the
                   concurrent-write loss: a fact write_fact-acked (ok:true)
                   while a compaction sweep is between its snapshot read and its
                   engine swap is silently dropped from the store. This is the
                   data-loss path the gate disables by default.

Never touches the standing 127.0.0.1:7401 service. Uses port 7431 + a temp data
dir and proves no listener remains afterwards.
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
DATA_DIR = "compaction_loss_data"
LOG_PATH = "compaction_loss_daemon.log"
BINARY = "./target/release/tbackend"
STORE = "ledger_loss"
TARGET_STORE = "ledger_loss_rollup"

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
        header = recvall(sock, 4)
        length = struct.unpack(">I", header)[0]
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


def key_present(key):
    resp = one_req({"op": "facts_for", "store": STORE, "key": key})
    return resp.get("ok") and len(resp.get("facts", [])) > 0


def start_daemon(unsafe_compaction):
    shutil.rmtree(DATA_DIR, ignore_errors=True)
    try:
        os.remove(LOG_PATH)
    except FileNotFoundError:
        pass
    log = open(LOG_PATH, "wb")
    args = [BINARY, "--host", HOST, "--port", str(PORT), "--data-dir", DATA_DIR, "--pool-size", "8"]
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


def stop_daemon(proc):
    if proc.poll() is None:
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


def listener_present():
    try:
        socket.create_connection((HOST, PORT), timeout=1.0).close()
        return True
    except Exception:
        return False


# ── Phase 1: gate refuses by default ─────────────────────────────────────────

def phase_gate():
    print("\n== Phase 1: default daemon must refuse compaction ==")
    proc = start_daemon(unsafe_compaction=False)
    try:
        now = time.time()
        write_fact(make_fact("warm:1", now, "p"))
        write_fact(make_fact("cold:1", now - 100000.0, "p"))
        policy_id = create_policy()
        resp = one_req({"op": "snapshot_trigger", "policy_id": policy_id})
        check(resp.get("ok") is False, f"snapshot_trigger refused (ok={resp.get('ok')})")
        check(resp.get("error_code") == "compaction_disabled_unsafe",
              f"refusal carries compaction_disabled_unsafe (got {resp.get('error_code')})")
        # auto-sweep must not have run either: wait > one 5s tick and confirm no loss
        size_before = store_size()
        time.sleep(6.0)
        check(store_size() == size_before,
              f"no background sweep ran in 6s (size stable at {size_before})")
    finally:
        stop_daemon(proc)


# ── Phase 2: unsafe compaction drops a concurrent write ───────────────────────

def phase_loss():
    print("\n== Phase 2: --unsafe-compaction true drops concurrent writes (B3) ==")
    proc = start_daemon(unsafe_compaction=True)
    try:
        now = time.time()
        # 1 cold fact so compaction actually performs the swap.
        write_fact(make_fact("cold:1", now - 100000.0, "cold"))
        # Many warm facts to widen the read->build->swap window.
        warm_seed = 30000
        print(f"  seeding {warm_seed} warm facts to widen the compaction window...")
        # fast bulk seed on a single persistent socket
        with socket.create_connection((HOST, PORT), timeout=5.0) as sock:
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            sock.settimeout(10.0)
            for n in range(warm_seed):
                f = make_fact(f"warm:{n}", now, "warm")
                sock.sendall(encode_frame({"op": "write_fact", "fact": f}))
                length = struct.unpack(">I", recvall(sock, 4))[0]
                recvall(sock, length)
                recvall(sock, 4)
        policy_id = create_policy()

        acked, lost = [], []
        rounds = 3
        for r in range(rounds):
            # reseed the cold fact so each round has something to prune/swap
            write_fact(make_fact(f"cold:r{r}", now - 100000.0, "cold"))
            done = threading.Event()
            result = {}

            def trigger():
                result["resp"] = one_req({"op": "snapshot_trigger", "policy_id": policy_id})
                done.set()

            t = threading.Thread(target=trigger)
            t.start()
            # Spam canary writes during the sweep's build window.
            i = 0
            round_acked = []
            while not done.is_set():
                key = f"canary:r{r}:{i}"
                resp = write_fact(make_fact(key, time.time(), "canary"))
                if resp.get("ok"):
                    round_acked.append(key)
                i += 1
            t.join()
            # Check survival of each acked canary AFTER the swap completed.
            for key in round_acked:
                acked.append(key)
                if not key_present(key):
                    lost.append(key)
            print(f"  round {r}: acked {len(round_acked)} canaries, "
                  f"swap result ok={result.get('resp', {}).get('ok')}")

        print(f"  total acked canaries: {len(acked)}; silently lost after compaction: {len(lost)}")
        check(len(acked) > 0, "canary writes were acked during compaction")
        check(len(lost) > 0,
              f"at least one ACKED write was silently lost by unsafe compaction (lost={len(lost)})")
    finally:
        stop_daemon(proc)


def main():
    if not os.access(BINARY, os.X_OK):
        raise SystemExit(f"daemon binary not found/executable at {BINARY}")
    try:
        phase_gate()
        phase_loss()
    finally:
        check(not listener_present(), f"no daemon listener remains on port {PORT}")
        shutil.rmtree(DATA_DIR, ignore_errors=True)
        try:
            os.remove(LOG_PATH)
        except FileNotFoundError:
            pass

    print("\n" + ("ALL COMPACTION GATE/LOSS TESTS PASSED" if FAILED == 0
                  else f"{FAILED} COMPACTION TEST(S) FAILED"))
    raise SystemExit(0 if FAILED == 0 else 1)


if __name__ == "__main__":
    main()
