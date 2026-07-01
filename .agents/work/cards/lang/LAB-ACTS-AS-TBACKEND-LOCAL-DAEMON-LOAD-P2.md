# LAB-ACTS-AS-TBACKEND-LOCAL-DAEMON-LOAD-P2 — local daemon load proof for Ruby connector

Status: CLOSED
Lane: tbackend / ruby connector / business pressure
Type: implementation + measurement
Delegation code: OPUS-ACTS-AS-TBACKEND-LOCAL-DAEMON-LOAD-P2
Date: 2026-07-01
Skill: idd-agent-protocol

## Context

P1 closed the connector refresh:

- `acts-as-tbackend` core is now pooled, circuit-broken, idempotent, and hash-result-shaped.
- Rails mirror path is ported to `Mirror.build_fact` + `client.write_fact_once_safe`.
- Down-daemon behavior is soft/non-fatal.
- Unit suite is green without a live daemon.

But the README throughput sentence is still an expectation:

```text
Persistent pooled sockets + TCP_NODELAY make 5-8k rpm modest.
```

This card turns that sentence into local evidence. Start a **local loopback**
`tbackend` daemon, drive the new Ruby connector against it, measure status mix and
latency, and report whether the connector/daemon pair is ready for Spark-shaped
shadow mirror experiments.

## Goal

Produce a repeatable local load proof for:

```text
acts-as-tbackend Client/Pool/Mirror -> local tbackend daemon -> write_fact_once
```

Acceptance target is not a marketing benchmark. The target is a useful operational
envelope:

- can the connector sustain at least 5-8k rpm locally with accepted durability?
- what is p50/p95/p99 latency?
- what statuses appear (`committed_acked`, `idempotent_replay`, `rejected_before_commit`,
  `timeout_unknown`, `unavailable`, `circuit_open`)?
- does bounded backpressure produce retryable soft failures rather than Rails-path exceptions?
- does durable mode behave correctly but slower?

## Current Authority

- TBackend daemon behavior: `igniter-tbackend/` live Rust source.
- Ruby connector behavior: `runtime/acts-as-tbackend/` live source.
- Production authority: **closed**. This is local evidence only.
- SparkCRM authority: **closed**. Do not read or write SparkCRM.

## Verify First

Read live files before coding:

- `runtime/acts-as-tbackend/README.md`
- `runtime/acts-as-tbackend/lib/acts_as_tbackend/{client,pool,connection,fact,mirror,config}.rb`
- `runtime/acts-as-tbackend/test/*_test.rb`
- `igniter-tbackend/README.md`
- `igniter-tbackend/Cargo.toml`
- `igniter-tbackend/tbackend.config.json`
- `igniter-tbackend/src/main.rs`
- `igniter-tbackend/src/server.rs`

Confirm exact daemon command. Current expected shape:

```text
cd igniter-tbackend
cargo build --release --bin tbackend
./target/release/tbackend --host 127.0.0.1 --port <free-port> --data-dir <tmpdir> \
  --durability accepted --max-inflight-requests <N>
```

Do not assume port `7401` is free. Pick an ephemeral high port and print it.

## Scope

Allowed:

- Add a focused load driver under `runtime/acts-as-tbackend/`, preferably
  `scripts/load_local_daemon.rb` or `test/load_local_daemon_test.rb`.
- Add a short doc/proof packet under `runtime/acts-as-tbackend/docs/` or update
  README with a "Local load proof" section if the evidence is stable enough.
- Start/stop a local loopback daemon process in `/tmp` or a repo-ignored temp dir.
- Build `igniter-tbackend` release binary if needed.
- Use only synthetic stores/keys/facts.

Closed:

- No SparkCRM code/data.
- No production traffic.
- No lab machines, Tailscale, Docker/AWS, or remote hosts.
- No daemon source changes unless a hard blocker is found; if found, stop and
  write the exact blocker/follow-up card.
- No changing the connector public API unless the load proof exposes a correctness
  bug that cannot be measured otherwise.

## Implementation Guidance

Prefer a small Ruby driver using the connector itself, not a separate socket client.

Suggested CLI:

```text
ruby -Ilib scripts/load_local_daemon.rb \
  --port auto \
  --writes 10000 \
  --threads 8 \
  --pool-size 8 \
  --durability accepted \
  --max-inflight 256
```

Driver responsibilities:

1. Build/start local `tbackend` if a daemon is not already supplied.
2. Wait for `ActsAsTbackend.client.ping` to return ok.
3. Generate deterministic synthetic facts via `Fact.derive_id` + `Fact.build`.
4. Drive writes concurrently through `ActsAsTbackend.client.write_fact_once_safe`.
5. Record per-write latency using monotonic time.
6. Summarize:
   - total writes attempted;
   - success count;
   - replay count;
   - status counts;
   - errors grouped by status/error;
   - elapsed seconds;
   - writes/sec and rpm;
   - p50/p95/p99/max latency;
   - daemon pid/port/data-dir;
   - daemon stderr tail on failure.
7. Stop daemon and remove temp data unless `KEEP_TBACKEND_LOAD_ARTIFACTS=1`.

Keep the output both human-readable and machine-readable. A final JSON line or
`--json` mode is ideal.

## Required Scenarios

Run all scenarios locally unless blocked:

### A. Accepted durability baseline

```text
writes: 10_000
threads: 8
pool_size: 8
durability: accepted
max_inflight_requests: 256 or 0
```

Expected: mostly/all `committed_acked`; rpm comfortably above 5-8k unless local
machine is unusually constrained.

### B. Idempotent replay

Repeat the same deterministic fact ids.

Expected: `idempotent_replay` for repeated writes; no duplicate conflict.

### C. Backpressure / overload

Use a low `--max-inflight-requests` and higher client concurrency.

Expected: `rejected_before_commit` / retryable soft statuses may appear; no Ruby
exceptions escaping the driver; circuit breaker only opens if the daemon becomes
unreachable or persistent transport errors occur.

### D. Durable mode sample

Run a smaller sample, e.g. `writes: 1000`, `durability: durable`.

Expected: correct committed responses; slower latency; no timeout storm. If it is
too slow locally, report the measured envelope and stop.

## Required Commands

From `runtime/acts-as-tbackend`:

```text
ruby -c lib/acts_as_tbackend.rb
for f in lib/acts_as_tbackend/*.rb; do ruby -c "$f"; done
ruby -Ilib:test -e 'ARGV.each { |f| require File.expand_path(f) }' test/*_test.rb
gem build acts-as-tbackend.gemspec
```

Remove generated `.gem` artifacts after the smoke.

From `igniter-tbackend`:

```text
cargo build --release --bin tbackend
```

Then run the new load driver for scenarios A-D.

Also run:

```text
git diff --check -- runtime/acts-as-tbackend .agents/work/cards/lang/LAB-ACTS-AS-TBACKEND-LOCAL-DAEMON-LOAD-P2.md
```

## Acceptance

- [ ] Load driver exists and uses `ActsAsTbackend::Client` / `Fact`, not a bespoke protocol client.
- [ ] Driver starts/stops a local loopback daemon or clearly supports an already-running local daemon.
- [ ] Scenario A measured and reported with status counts + latency percentiles.
- [ ] Scenario B proves idempotent replay with repeated ids.
- [ ] Scenario C proves overload/backpressure is soft and classified.
- [ ] Scenario D gives a durable-mode sample or a precise blocker.
- [ ] No SparkCRM, production, remote hosts, Tailscale, or Docker/AWS touched.
- [ ] `.gem` artifacts and temp daemon data are not left in git.
- [ ] README/proof doc states measured envelope honestly; no stable production claim.
- [ ] Existing Ruby unit suite still passes.
- [ ] `git diff --check` clean.

## Stop Conditions

Stop and report instead of papering over if:

- local daemon cannot start cleanly;
- connector protocol disagrees with daemon protocol;
- writes can hang indefinitely;
- exceptions escape the supposedly soft write path;
- duplicate deterministic ids create conflicts instead of replays;
- overload creates hard failures instead of retryable soft status.

If a stop condition is hit, write the exact failure shape and propose the next
card, likely in `igniter-tbackend` or connector protocol mapping.

## Non-goals

- No claim that SparkCRM is ready to enable the mirror.
- No production runbook.
- No async queue/Sidekiq path.
- No remote lab benchmark.
- No daemon optimization unless required to make the proof possible.
- No package release.

## Closing Report

**CLOSED 2026-07-01.** Local load proof turned the README expectation into measured evidence. Full envelope
in `docs/local-load-proof.md`.

```text
Result (single macOS dev box, loopback, release tbackend):
- accepted baseline: 2,214,496 rpm (36,908/s) · p50 0.20 / p95 0.40 / p99 0.52 / max 2.78 ms
    · status: committed_acked 10000 (0 errors)   -> ~300x the 5-8k rpm target
- replay: pass 2 same deterministic ids -> idempotent_replay 10000, 0 duplicate_fact_id_conflict
- overload (--max-inflight 4, 32 threads): SOFT — committed_acked 9952 · timeout_unknown 32 (safe-retried;
    15 recovered as idempotent_replay) · rejected_before_commit 1 · zero Ruby exceptions.
    Cost = tail latency (max ~10 s = 2x 5 s request timeouts), not crashes: the daemon's global write lock
    serializes rather than shedding hard at in-flight=4. Size max-inflight/request_timeout for real concurrency.
- durable sample (1000 writes, durability=durable): committed_acked 1000 · p50 9.06 / p99 11.99 / max 19.49 ms
    · 51,905 rpm — correct + ~45x slower per write (group-commit fdatasync), no timeout storm, ~7x the target.

Changed (all under runtime/acts-as-tbackend/):
- scripts/load_local_daemon.rb (new) — driver using ActsAsTbackend::Client + Fact (no bespoke socket client);
  ephemeral port, tmp data-dir, per-write monotonic latency, status mix, p50/p95/p99/max, --json, auto cleanup
  (KEEP_TBACKEND_LOAD_ARTIFACTS=1 to keep), TERM->KILL daemon stop, daemon-log tail on ping failure.
- docs/local-load-proof.md (new) — honest measured envelope + reproduce command + "local evidence only".

Verified:
- ruby -c lib + scripts driver: OK · unit suite: 12 runs / 37 assertions / 0 fail (still green)
- gem build 0.2.0 OK, .gem removed · no leftover daemons, no temp load dirs (cleanup confirmed)
- daemon command: ./target/release/tbackend --host 127.0.0.1 --port <auto> --data-dir <tmp>/data
    --durability <accepted|durable> --max-inflight-requests <N>   (cargo build --release --bin tbackend: up-to-date)
- git diff --check -- runtime/acts-as-tbackend <card>: clean (exit 0)

Decision:
- READY for Spark-shaped shadow-mirror experiments — wide headroom over the operational target, correct
  idempotency, soft/classified backpressure, working durable mode; no stop conditions hit.
- next card: LAB-ACTS-AS-TBACKEND-RAILS-SYNTHETIC-SHADOW-P3 (tiny synthetic AR app using the extension
  against a local daemon — proves the full in-request Rails mirror path, not raw throughput).
```

Scope kept: no SparkCRM, no production, no lab/Tailscale/Docker, no daemon source changes, no connector
API changes, no package release.

## Likely Next Cards

- `LAB-ACTS-AS-TBACKEND-RAILS-SYNTHETIC-SHADOW-P3` — tiny synthetic ActiveRecord app
  using the extension against local daemon.
- `LAB-ACTS-AS-TBACKEND-ASYNC-JOB-P4` — optional app-owned Sidekiq/job helper if
  synchronous callback latency is too high.
- `LAB-TBACKEND-RUBY-CONNECTOR-PROTOCOL-FIX-P*` — only if this card finds a protocol
  or status-mapping mismatch.
