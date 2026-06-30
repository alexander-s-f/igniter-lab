# TBackend User Guide & Quick Start

This guide records operator examples for TBackend: a standalone temporal
ledger and reactive pipeline substrate used by Igniter Lab proofs and
Spark-shaped shadow systems.

Current status:

```text
implemented lab substrate
  -> shadow-ready candidate for side-ledger work
  -> production promotion only after convergence gates
```

This is not public service documentation and does not promise stable API,
production authority, or performance behavior. It **does** document a legitimate
local daemon/client seam for bounded shadow deployments where the main
application remains authoritative.

---

## 1. Quick Start & Basic Operations

### A. Compilation
TBackend is written in pure Rust with no external Rust crate dependencies beyond Cargo-managed package dependencies.
1.  **Clone/Navigate** to `igniter-lab/igniter-tbackend`.
2.  **Compile** the standalone release binary:
    ```bash
    RUSTFLAGS="-C link-arg=-undefined -C link-arg=dynamic_lookup" cargo build --release
    ```
    The compiled binary will be placed at: `target/release/tbackend`.

### B. Booting the Daemon
TBackend can be configured using command-line arguments or a JSON configuration file.

*   **Standard Local Launch** (durable storage in `data/`, 16 thread workers, **auth disabled**):
    ```bash
    ./target/release/tbackend --host 127.0.0.1 --port 7401 --data-dir data --pool-size 16
    ```
*   **Secure Local Launch** (durable storage in `data/`, **auth enabled**):
    ```bash
    ./target/release/tbackend --host 127.0.0.1 --port 7401 --data-dir data --pool-size 16 --auth-enabled true
    ```
*   **Ephemeral Launch** (in-memory only, perfect for unit testing):
    ```bash
    ./target/release/tbackend --host 127.0.0.1 --port 7401 --data-dir nil
    ```
*   **Config-driven Launch**:
    ```bash
    ./target/release/tbackend --config tbackend.config.json
    ```

> [!NOTE]
> When launching with `--auth-enabled true` for the first time (with a `--data-dir`), TBackend mints a **random** one-time administrator token with wildcard permissions. Only its hash is persisted (`data/security/<hash>.json`); the plaintext is written **once** to `data/security/BOOTSTRAP_ADMIN_TOKEN` (mode `0600`). Read it, use it to create your real tokens, then delete the handoff file. There is no fixed default token.

### C. Launching the Administrative Time-Traveling REPL
TBackend comes with a FFI-free pure-Ruby administrative REPL shell supporting tab completion and command history:
```bash
ruby tbackend_repl.rb
```
*REPL Console Session:*
```text
(127.0.0.1:7401) tbackend> ping
✔ Pong! Network wire latency: 0.06 ms

(127.0.0.1:7401) tbackend> put lead_signals lead-1 '{"vendor":"eLocal","zip":"90210"}'
✔ Fact successfully written! Latency: 0.22 ms

(127.0.0.1:7401) tbackend> list lead_signals
┌──────────────────────────────────────┬──────────────────────┬─────────────┬───────────┬────────────────────────────────────────────────────────┐
│ Fact ID                              │ Key                  │ Tx Time     │ Val Time  │ Payload                                                │
├──────────────────────────────────────┼──────────────────────┼─────────────┼───────────┼────────────────────────────────────────────────────────┤
│ d08f43be-512c-4cf2-83de-a89e4912ab02 │ lead-matching-1      │ 11:27:04    │ 11:27:04  │ {"vendor":"eLocal","zip":"90210"}                      │
└──────────────────────────────────────┴──────────────────────┴─────────────┴───────────┴────────────────────────────────────────────────────────┘
```

---

## 2. Dynamic JSON API Payload Schemas

TBackend communicates using a big-endian length-framed CRC32 JSON wire protocol over TCP. Below are the standard payload schemas:

> [!IMPORTANT]
> When `--auth-enabled true` is active, **every standard request payload must include a valid `"token"` parameter** at the root of the JSON object.

### A. Committing Facts (`write_fact`)
Writes a bitemporal fact to a dynamic store.
```json
{
  "op": "write_fact",
  "token": "write_token",
  "fact": {
    "id": "e0b968fc-bf4b-47e1-8898-1e42a912bb01",
    "store": "lead_signals",
    "key": "lead-1",
    "value": { "vendor_name": "eLocal", "zip_code": "91125", "partner_id": "partner-101" },
    "value_hash": "stable-hash-string",
    "transaction_time": 1780387174.5,
    "valid_time": 1780387174.5,
    "schema_version": 1
  }
}
```

### A2. Idempotent Durable Write (`write_fact_once`) — recommended

The durable, idempotent write path (prefer this over `write_fact` for any ledger/shadow use). The server **stamps a canonical Blake3 `value_hash`** and **assigns a per-store monotonic `seq_id`** (the ordering authority), then dedups by `(store, id)`. Derive a **stable, domain-deterministic `id`** (e.g. `store:record_id:event_type:source_version`) so a retry re-sends the same id and collapses to a replay instead of a duplicate. **Never put wall-clock in the id** — it breaks idempotency.

```json
{
  "op": "write_fact_once",
  "durability": "durable",
  "fact": {
    "id": "availability:tech-7:slot.blocked:1782277159",
    "store": "availability",
    "key": "tech-7",
    "value": { "slot": 540, "state": "blocked", "reason": "scheduled" },
    "transaction_time": 1780387174.5,
    "valid_time": 1782277200.0,
    "schema_version": 1
  }
}
```
Response:
```json
{ "ok": true, "committed": true, "durability": "durable", "idempotent_replay": false, "seq_id": 42 }
```
- `idempotent_replay: true` — the same id + content was already written; **no duplicate**, the original `seq_id` is returned.
- `error_code: "duplicate_fact_id_conflict"` — same id, *different* content (a real conflict; not retryable).
- `durability`: `"accepted"` (default — OS page cache, survives process crash not power loss) or `"durable"` (blocks until a group-commit `fdatasync` covers the write). On an ephemeral (no-WAL) daemon, `durable` honestly downgrades to `"in_memory"`. A failed sync returns `committed:false, retryable:true` — never a false durable ack.

### A3. Clock-Free Ordered Read (`facts_by_seq`)

Reads facts in **server `seq_id` order** (the ordering authority), independent of wall-clock — correct under backfills, corrections, and replays. Use this for replay/audit instead of ordering by `transaction_time`.
```json
{ "op": "facts_by_seq", "store": "availability", "after_seq": 0, "until_seq": null }
```

### B. Pointwise Temporal Lookup (`latest_for`)
Queries the active state of a key at a specific `as_of` transaction timestamp (time-travel). Omitting `as_of` queries the present coordinate.
```json
{
  "op": "latest_for",
  "store": "lead_signals",
  "key": "lead-1",
  "as_of": 1780387175.0
}
```

### C. Synchronous Multi-Store Query (`cross_store_query`)
Queries multiple store partitions simultaneously at a shared time-travel coordinate in a single round-trip.
```json
{
  "op": "cross_store_query",
  "queries": [
    { "store": "orders", "key": "order-101" },
    { "store": "agents", "key": "agent-alpha" }
  ],
  "as_of": 1780387175.0
}
```

### D. Relational Temporal Joins (`cross_store_join`)
Executes an `inner` or `left` join between a `left_store` and a `right_store` at a shared `as_of` coordinate, matching fields based on a join key.
```json
{
  "op": "cross_store_join",
  "join_type": "left",
  "left_store": "orders",
  "right_store": "agents",
  "left_key_path": "value.agent_ref",
  "right_key_path": "key",
  "as_of": 1780387175.0
}
```

### E. Bitemporal Temporal Query & Rules Pushdown Slicing (`query_slice`)
Queries and slices bitemporal timelines natively. Supports a `rules` pushdown filter array to evaluate complex conditional rules (such as numerical inequalities `gt`, `lt`, `eq`, `ne`, `ge`, `le`) directly in Rust, avoiding heavy network and FFI serialization.
```json
{
  "op": "query_slice",
  "token": "read_token",
  "store": "lead_signals",
  "since_val": 1780336800.0,
  "as_of_val": 1780344000.0,
  "rules": [
    { "left_path": "value.zip_code", "op": "eq", "right_val": "91125" },
    { "left_path": "value.bid", "op": "gt", "right_val": 18 },
    { "left_path": "value.bid", "op": "lt", "right_val": 24 }
  ]
}
```

### F. Declarative Reactive Pipelines (`pipeline_create`)
Creates an event pipeline matching a triggering store. Obtains associated states from combined stores, evaluates rule predicates, transforms payloads using a JSON template, and streams or triggers webhooks out-of-band.
```json
{
  "op": "pipeline_create",
  "trigger_store": "lead_signals",
  "combines": [
    { "store": "availabilities", "key_path": "lead_signals.value.partner_id", "alias": "avail" },
    { "store": "balances", "key_path": "lead_signals.value.partner_id", "alias": "bal" }
  ],
  "rules": [
    { "left_path": "lead_signals.value.zip_code", "op": "eq", "right_val": "91125" },
    { "left_path": "avail.value.count", "op": "gt", "right_val": 10 },
    { "left_path": "bal.value.amount", "op": "gt", "right_val": 1000 }
  ],
  "transform_template": {
    "lead_id": "{{lead_signals.id}}",
    "status": "approved",
    "stats": {
      "avail": "{{avail.value.count}}",
      "bal": "{{bal.value.amount}}"
      }
  },
  "action_target_store": "approved_leads",
  "action_webhook_url": "http://127.0.0.1:8080/leads",
  "persist": true
}
```

### G. Dynamic Token Creation (`auth_token_create`)
Creates a new security token with a specified role and store ACL whitelists. The bearer token is
**generated server-side** and returned **once** in the response (`token`) alongside an opaque `id`;
the plaintext is never stored or echoed again. Callers must **not** supply `target_token`.
```json
{
  "op": "auth_token_create",
  "token": "<admin-token>",
  "target_role": "read_only",
  "allowed_stores": ["financial_ledger"],
  "persist": true,
  "label": "finance-readonly"
}
```
Response (shown once):
```json
{ "ok": true, "token": "<new-token>", "id": "<opaque-id>", "role": "read_only", "allowed_stores": ["financial_ledger"], "persist": true }
```

### H. Security Token Auditing (`auth_token_list`)
Lists registered tokens as metadata only — opaque `id`, `role`, `allowed_stores`, `persist`, and a
`count`. It never returns a token value or hash.
```json
{
  "op": "auth_token_list",
  "token": "<admin-token>"
}
```

### I. Security Token Deletion (`auth_token_delete`)
Deletes an active token from memory and persistent disk registry, addressed by the opaque `id` from
`auth_token_list`. Deleting the last remaining admin is refused (lockout prevention).
```json
{
  "op": "auth_token_delete",
  "token": "<admin-token>",
  "target_id": "<id-from-list>"
}
```

---

## 3. Lab Scenario Sketches

### Use Case A: Side-Ledger Audit & Explainability (SparkCRM)
A mature Rails/Postgres system can mirror selected lifecycle events to
TBackend without changing the business write path. The first production-shaped
role is **shadow side-ledger**, not replacement:

1.  Rails/Postgres write remains authoritative.
2.  An after-commit/outbox path writes bounded facts to TBackend.
3.  TBackend answers point-in-time and lineage questions such as "why was this
    technician unavailable at this slot?"
4.  Shadow projections compare TBackend-derived summaries against the
    ActiveRecord reference.
5.  Convergence/stability evidence decides whether promotion is safe.

### Use Case B: Preventing Database Bloat & Compacting Logs (SparkCRM)
A high-write webhook workload can create write amplification and index pressure. Use `SnapshotPack` to automatically roll up old facts and reclaim disk space:
1.  **Register a Rollup Policy**: Group facts older than 3 days by ZIP code and vendor, aggregating average bid prices and counts.
2.  **Compact disk space (safe manual)**: Compaction is **off by default and operator-triggered** (`--enable-compaction`; the unsafe 5s auto-sweep was removed — it silently lost concurrent acked writes). When triggered it runs under a **per-store stop-the-world gate** (drains in-flight writes, so no acked write is lost) and a **durable rename** (`fsync(tmp) → rename → fsync(dir) → swap`), pruning cold facts, compiling summaries, and shrinking the WAL while preserving `seq_id`.

### Use Case C: Out-of-Band Reactive Workflows (MobX/ROP)
Execute complex business rules dynamically without GVL blocking inside your core app:
1.  Use `PipelinePack` to register a reactive pipeline over TCP.
2.  Incoming webhook events trigger the pipeline immediately.
3.  The server gathers auxiliary contexts (e.g. looking up partner balances and slot availabilities) and runs checks out-of-band.
4.  If approved, a microservice webhook callback fires with a compiled JSON payload, while rejected events are short-circuited instantly without writing a target fact.

### Use Case D: Edge Swarms & Distributed Synchronization (RPi5 / ESP32)
Deploy standalone lightweight TBackend binaries to independent IoT devices:
1.  Configure the node peers list using the `--peers 192.168.1.50:7401,192.168.1.51:7401` flag.
2.  Devices gossip, exchange state vectors, and replicate missing WAL timelines. **Caveat (current):** gossip replication still pulls by client `transaction_time`, so under cross-node **clock skew it can silently drop writes** — the seq-watermark fix (`LAB-TBACKEND-MESH-SEQ-WATERMARK-P13`) is designed but **not yet wired**. Treat the multi-node mesh as **readiness-stage**, not production-convergent, until it lands.

### Use Case E: Secure Multi-Tenant Ledger Isolation (SparkCRM Migration)
Securely isolate sensitive business ledgers and restrict client access on shared infrastructure:
1.  **Enable Hardened Security**: Boot TBackend with `--auth-enabled true`.
2.  **Isolate Operations by Role**: Create a `write_only` token (`write_token`) restricted to the `lead_signals` partition for ingestion webhooks, and a `read_only` token (`finance_token`) restricted to `financial_ledger` for reporting services.
3.  **Audit Security Trails**: Middleware logs raw connection requests, validating role capabilities and partition ACLs through the in-memory authorization path, preventing partition cross-talk in the lab model.

---

## 4. Lab Service Control Plane CLI

Administrators can operate TBackend as a daemon process using `tbackend_service.rb` inside the project folder:

```bash
# 1. Boot the TBackend server in the background
ruby tbackend_service.rb start
# ✔ TBackend Server started in background! PID: 92842

# 2. Query process details and live metrics dashboard
ruby tbackend_service.rb status

# 3. View live system logs
ruby tbackend_service.rb log

# 4. Gracefully shutdown the server and sync all WAL segments
ruby tbackend_service.rb stop
# ✔ TBackend Server stopped successfully.
```

---

## 5. Native Model Context Protocol (MCP) Integration (`McpPack`)

TBackend includes a native, lightweight, zero-dependency **Model Context Protocol (MCP)** stdio server wrapper. This allows MCP-compatible clients to connect directly to TBackend, discover active ledgers, perform pointwise time-travel queries, write facts, and execute server-side pushdown slices without custom APIs.

### A. Booting the Daemon in MCP Subprocess Mode
To launch the TBackend server in stdio-based MCP mode:
```bash
./target/release/tbackend --mcp --data-dir data
```
*   **Log Redirection**: The daemon automatically duplicates and redirects all standard logs, banners, and debug output to standard error (`stderr`), keeping standard output (`stdout`) pristine for JSON-RPC 2.0 frames.
*   **Security Integration**: You can combine MCP with Token Security by running `./target/release/tbackend --mcp --data-dir data --auth-enabled true`. All tools will accept an optional `"token"` argument whitelisting access.

### B. Exposed MCP Tools
Once connected, TBackend exposes the following structured tools to the LLM agent:

1.  **`tbackend_write_fact`**: Commits a new bitemporal fact. Automatically generates UUID `id`, `transaction_time` timestamp, and Blake3 payload `value_hash` if they are omitted by the AI agent.
2.  **`tbackend_latest_for`**: Point pointwise bitemporal point lookup (time-travel).
3.  **`tbackend_query_slice`**: Valid-time timeline slice query with server-side ROP pushdown filters.
4.  **`tbackend_analytics_aggregate`**: Groups facts and calculates metrics (`count`, `sum`, `avg`, `min`, `max`, `cardinality`) natively.
5.  **`tbackend_pipeline_create`**: Installs an out-of-band reactive MobX-style combine/evaluate pipeline.
6.  **`tbackend_diagnostics_summary`**: Retrieves partition diagnostic metrics and RAM footprint allocations.

### C. Example Cursor / Claude Desktop Integration Config
Add the following block to your `claude_desktop_config.json` or Cursor custom MCP server settings:
```json
{
  "mcpServers": {
    "tbackend": {
      "command": "./target/release/tbackend",
      "args": ["--mcp", "--data-dir", "./data"]
    }
  }
}
```
Now, your AI agent can query and write directly to your database partitions using natural language!
