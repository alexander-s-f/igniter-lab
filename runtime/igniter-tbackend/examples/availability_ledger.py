#!/usr/bin/env python3
"""
Example usecase — a bitemporal availability audit ledger on TBackend.

Shows what TBackend gives you that a plain UPDATE-in-place table does not:

  1. idempotent durable append    write_fact_once + durability:"durable"
  2. retry-safe writes            same domain-derived id  -> replay, never a duplicate
  3. point-in-time / time-travel  latest_for(as_of): "what did we know at time T?"
  4. clock-free audit order       facts_by_seq (server seq_id, not wall-clock)
  5. lineage / explainability     "why was this slot blocked, and when did we learn it?"

The domain: a contractor's technician has schedule slots. Slots get blocked
(scheduled / off-schedule) and later corrected. Instead of overwriting a row,
every change is an append-only *fact*; the ledger can replay the exact state
visible at any past coordinate and explain each decision.

Run a daemon first (ephemeral in-memory is fine for the demo; use --data-dir
for the durable path):

    cargo build --release --bin tbackend
    ./target/release/tbackend --host 127.0.0.1 --port 7401 --data-dir data

Then:

    python3 examples/availability_ledger.py

This is lab/example code, not production client code.
"""
import json
import socket
import struct
import sys
import time
import zlib

HOST, PORT, STORE = "127.0.0.1", 7401, "availability_demo"


# ── wire protocol: big-endian length-prefix + JSON body + CRC32 (see docs §4.A) ──
def call(payload):
    """One length-prefixed, CRC32-validated JSON round-trip over TCP."""
    body = json.dumps(payload).encode()
    frame = struct.pack(">I", len(body)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)
    with socket.create_connection((HOST, PORT), timeout=5) as s:
        s.sendall(frame)
        n = struct.unpack(">I", _recv(s, 4))[0]
        resp = _recv(s, n)
        _recv(s, 4)  # trailing CRC of the response (not re-checked in this demo)
        return json.loads(resp)


def _recv(s, n):
    buf = b""
    while len(buf) < n:
        chunk = s.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("short read — connection closed mid-frame")
        buf += chunk
    return buf


# ── domain helpers ───────────────────────────────────────────────────────────
def fact_id(tech, kind, version):
    """DOMAIN-DETERMINISTIC id.

    A retry recomputes the SAME id -> idempotent replay, never a duplicate.
    `version` is a stable domain version (think updated_at / lock_version), NOT
    a wall-clock — wall-clock in the id would silently break idempotency.
    """
    return f"{STORE}:{tech}:{kind}:{version}"


def write_slot(tech, slot, state, reason, valid_at, tx_at, version, durability="durable"):
    return call({
        "op": "write_fact_once",
        "durability": durability,
        "fact": {
            "id": fact_id(tech, f"slot.{state}", version),
            "store": STORE,
            "key": tech,
            "value": {"slot": slot, "state": state, "reason": reason},
            # transaction_time = when the fact was RECORDED = the `as_of` (time-travel)
            # axis used by latest_for. It is client-supplied (evidence, NOT the ordering
            # authority — seq_id is). Set explicitly here so the demo can query *between*
            # two recordings; in production it is clock-stamped at write time.
            "transaction_time": tx_at,
            "valid_time": valid_at,  # when the fact is true in the domain
            "schema_version": 1,
        },
    })


def value_of(resp):
    return resp["fact"]["value"] if resp.get("fact") else None


def main():
    t0 = 1782277200.0  # a fixed base recording-time coordinate for the demo

    print("== 1. idempotent durable append ==")
    r1 = write_slot("tech-7", 540, "blocked", "scheduled", valid_at=t0, tx_at=t0, version=1)
    print("  first write :", r1)  # committed, idempotent_replay=false, durability=durable, seq_id=N

    print("== 2. retry the SAME logical write (e.g. timeout/redelivery) ==")
    r2 = write_slot("tech-7", 540, "blocked", "scheduled", valid_at=t0, tx_at=t0, version=1)
    print("  retry       :", r2)  # idempotent_replay=true, SAME seq_id, no duplicate
    assert r2.get("idempotent_replay") is True, "a retry of the same id+content must replay, not duplicate"

    # a later correction is a NEW fact (new domain version), recorded one hour later —
    # append-only, not an overwrite:
    write_slot("tech-7", 540, "available", "rescheduled", valid_at=t0 + 3600, tx_at=t0 + 3600, version=2)

    print("== 3. point-in-time (time-travel) — what did we know at each coordinate? ==")
    early = call({"op": "latest_for", "store": STORE, "key": "tech-7", "as_of": t0 + 10})    # before the correction
    now = call({"op": "latest_for", "store": STORE, "key": "tech-7", "as_of": t0 + 7200})    # after the correction
    print("  as_of early :", value_of(early))  # -> blocked (scheduled)
    print("  as_of now   :", value_of(now))    # -> available (rescheduled)

    print("== 4. clock-free audit order (facts_by_seq) ==")
    seq = call({"op": "facts_by_seq", "store": STORE, "after_seq": 0, "until_seq": None})
    for f in seq.get("facts", []):
        print(f"  seq={f['seq_id']}  vt={f['valid_time']:.0f}  {f['value']['state']} ({f['value']['reason']})")

    print("== 5. lineage — why was tech-7 unavailable at the early coordinate? ==")
    if early.get("fact"):
        f = early["fact"]
        print(f"  blocked because fact seq={f['seq_id']} (id={f['id']})")
        print(f"    recorded tt={f['transaction_time']:.0f} · valid_at={f['valid_time']:.0f} · reason={f['value']['reason']}")
        print("  -> a plain table would have overwritten this; the ledger explains it.")


if __name__ == "__main__":
    try:
        main()
    except (ConnectionError, OSError) as e:
        print(f"\nCould not reach TBackend at {HOST}:{PORT} — is the daemon running?\n  {e}", file=sys.stderr)
        sys.exit(1)
