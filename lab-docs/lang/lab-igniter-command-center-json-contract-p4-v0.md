# LAB-IGNITER-COMMAND-CENTER-JSON-CONTRACT-P4 — the v0 JSON / CI / MCP result contract

Lane: distribution / command center / structured output
Status: DONE (readiness + a small conformance test) — freezes the live shapes; no shape change, no Rust port
Date: 2026-07-01
Card: `.agents/work/cards/lang/LAB-IGNITER-COMMAND-CENTER-JSON-CONTRACT-P4.md`
Builds on: P1 autonomy packet · P2 `workspace status/doctor` · P3 `workspace build/test` · P10 doctor · P28 agent MCP envelope.

Authority boundary: this packet documents and pins the EXISTING structured output; it invents no new schema,
moves no authority, and does not switch the CLI shape. One low-risk conformance test is added.

---

## 1. Executive decision

**The contract already exists and works — freeze it, don't reinvent it.** Two deliberately-different
surfaces, both live and tested:

- **CLI `--json` = a bare JSON array of diagnostic records** `{scope,check,severity,detail,suggest}`
  (doctor + all `workspace` verbs). KEEP the bare array — switching to a top-level `{ok,command,records,
  summary}` envelope would break live consumers (the doctor + workspace wrapper tests assert the output
  `starts_with('[')`). A summary is trivially derivable downstream (count severities).
- **MCP = shape C** (P28): `content[0]` human text + `content[1]` a JSON envelope
  `{tool,ok,exit_code,stdout,stderr,parsed}`, plus a result-level `isError`. KEEP — confirmed live + tested.

If CI ever needs a single summary object from the CLI, add it as an **opt-in `--json-envelope`** (additive,
non-breaking), not by mutating the default array. Named as a future card, not done here.

## 2. Live JSON surfaces verified (2026-07-01)

| Surface | Owner | Shape (live) | Consumers / tests |
| --- | --- | --- | --- |
| `igniter doctor [--json]` | command center | **bare array** of records `{scope,check,severity,detail,suggest}` | `igniter_doctor_tests.rs` asserts `starts_with('[')`, ≥10 records, scopes env/toolchain/app |
| `igniter workspace status\|doctor\|build\|test [--json]` | command center | same record array (reuses `doc_emit`/`doc_render_json`) | `igniter_workspace_tests.rs` (9) asserts array + `scope:"workspace"` + schema keys |
| `igniter agent` MCP `tools/call` | command center (P28) | **shape C**: `content[0]`=text, `content[1]`=`{tool,ok,exit_code,stdout,stderr,parsed}`; `isError` | `igniter_agent_mcp_smoke_tests.rs` parses `content[1]` as the JSON envelope |
| `igniter stdlib list\|search\|show --json`, `explain --json` | **`igc`** (routing only) | igc's own JSON (the stdlib surface contract) | igc-owned; the center passes argv through, never re-parses |
| `igniter env doctor\|template\|check` | command center | human text only (names-only env catalogue); no `--json` today | `igniter_env_smoke_tests.rs` |

Verified mechanics: `doc_render_json` emits `{"scope","check","severity","detail","suggest"}` with
`suggest` as `null` (empty) or a JSON string, via a hand-rolled `json_escape`. Severity values actually
emitted across `bin/igniter`: **ok (16), warn (10), fail (8), info (7)** — exactly the documented vocabulary,
nothing else.

## 3. Canonical diagnostic record (frozen v0)

```json
{ "scope": "workspace", "check": "igniter-lang sibling", "severity": "ok",
  "detail": "../igniter-lang/docs/spec/stdlib-inventory.json present", "suggest": null }
```

- `scope` — a stable group key: `env` | `toolchain` | `app` | `workspace` (extend by adding new values,
  never by renaming existing ones).
- `check` — a short stable identifier for the specific check (human-labelled; treat as opaque, not parsed
  for meaning by agents — branch on `scope`+`severity`, show `detail`/`suggest`).
- `severity` — **exactly** `ok | info | warn | fail`. No other value is ever emitted.
- `detail` — human-readable one-liner (may contain paths, never secret/env values).
- `suggest` — `null` or a human-readable next action.

**CLI shape = a bare top-level array of these records.** Empty array is valid. This is the stable v0 CLI
contract for `doctor` + `workspace *`.

## 4. Which commands must support `--json`

- **Required (record array):** `doctor`, `workspace status|doctor|build|test`. All live. ✓
- **Owned elsewhere:** `stdlib *` / `explain` → `igc`'s JSON (do not duplicate/redefine in the center).
- **Not required v0:** `env *` (names-only text; alignment to a record array is a *candidate* future card,
  not a v0 requirement — it never prints values, so its text surface is already safe).
- **No `--json`:** `serve` / `check` (delegate to `igweb-serve`; their machine-readable signal is the exit
  code, and `check` failures are igweb-serve's contract).

## 5. Exit-code semantics (stable)

| Code | Meaning | Examples |
| --- | --- | --- |
| `0` | ran; no required gate failed | `doctor` (always a report), `workspace status`, healthy `workspace build/test` |
| `2` | usage error (bad flag/subcommand/positional) | `workspace build --quick`, `workspace test <positional>`, unknown verb |
| non-zero gate (`1`) | a **required LOCAL** check failed | `env check` (missing/empty required var), `workspace doctor` (missing core crate / Cargo.toml / canon sibling), `workspace build`/`test` (a build/test step failed) |

Rule: **remote / best-effort checks are `warn`, never a non-zero exit** for a local command (e.g. a mirror
HEAD lookup that can't reach SSH). Only an explicit gate (`env check`, `workspace doctor` local layout,
build/test steps) drives a non-zero exit. In MCP, `isError`/`exit_code` mirror this.

## 6. MCP shape (shape C — confirmed, unchanged)

```json
{ "content": [
    { "type": "text", "text": "<human summary>" },
    { "type": "text", "text": "{\"tool\":\"doctor\",\"ok\":true,\"exit_code\":0,\"stdout\":\"…\",\"stderr\":\"…\",\"parsed\":[ …records… ]}" }
  ],
  "isError": false }
```

- `content[0]` = human text (kept byte-compatible for older assertions).
- `content[1]` = the JSON envelope: `{tool, ok, exit_code, stdout(snippet), stderr(snippet), parsed}`.
  `parsed` carries the tool-specific structured payload — for the diagnostic tools it is the **record
  array** from §3, so agents get the same schema whether they call the CLI or the MCP tool.
- `exit_code` is `null` only for an argument-validation error that launched no command.
- **Agents consume `content[1]` (and `parsed`), never `content[0]`.**

## 7. Human-text vs machine-JSON boundary (explicit)

**Machine-readable (safe to parse):** the CLI `--json` record array; the MCP `content[1]` envelope + its
`parsed`. **Human-only (never parse):** the default text renders (`doc_render_text`, the `workspace
build/test` summaries), all `--help`/usage, and the cargo failure tails that `workspace build/test` write to
**STDERR** (stdout stays a clean record array under `--json`). Agents/CI that scrape human text are
out-of-contract and will break; use `--json` or MCP `parsed`.

## 8. Compatibility / migration

- **No shape change in this card.** The bare array and shape C are pinned as-is → zero migration.
- The `{ok,command,records,summary}` top-level envelope from the card's candidate section is **rejected for
  the default CLI** (breaks `starts_with('[')` consumers). It survives only as a possible **opt-in**
  `--json-envelope` later (additive). Documenting this keeps a future implementer from silently switching.
- Adding a new `scope` value or a new record is backward-compatible (consumers branch on known
  scopes/severities and ignore unknown ones). Renaming a `scope`/`severity` value is a breaking change and
  must not happen without a version bump.

## 9. Rust-CLI pressure — assessed, not over-claimed

Real but **not forcing** at v0. In favour of a port: `bin/igniter` hand-rolls `json_escape` + `doc_render_json`
(string-built JSON), which is correct today but fragile as fields grow. Against porting now: the shape is
tiny, stable, tested, and conformant; the record array + shape C cover every current consumer; a Rust port
is a large investment with no new capability. **Verdict: LOW-MODERATE pressure — monitor, don't port yet.**
The trigger is concrete: the first need for typed/streamed records, or the opt-in `--json-envelope` with a
computed summary, is where hand-rolled JSON stops paying — that is the moment for
`LAB-IGNITER-COMMAND-CENTER-RUST-CLI-READINESS-P5` (already named in P1).

## 10. Conformance test added (low-risk)

Per the card's "add a tiny conformance test if obvious", added
`server/igniter-web/tests/igniter_json_contract_tests.rs` — asserts the §3 invariants across the live
command-center JSON surfaces (`doctor --json`, `workspace status/doctor --json`) so the contract can't drift
silently: each is a bare top-level array; every record carries all five keys; every `severity` is in
`{ok,info,warn,fail}`; and no secret/env value leaks into records. Hermetic (workspace runs with
`IGNITER_WORKSPACE_NO_REMOTE=1`; doctor is local). This is the "agents never parse text" guard from P1 §8 /
P3's note, made executable.

## 11. Non-goals & next

Non-goals (honored): no shape change, no Rust port, no authority change, no forcing agents to parse text, no
silent JSON change. Next implementation cards (named, not started here):

- `LAB-IGNITER-COMMAND-CENTER-JSON-ENVELOPE-OPTIN-P5a` — *optional*, only if CI asks: an additive
  `--json-envelope` (`{ok,command,records,summary}`) over the record array; the default stays the bare array.
- `LAB-IGNITER-COMMAND-CENTER-RUST-CLI-READINESS-P5` — the Rust-CLI pivot (§9), evidence-gated.
- (candidate) `LAB-IGNITER-ENV-JSON-ALIGN-P6` — give `env doctor/check` a record-array `--json` if an
  operator/CI need appears; today its names-only text is already value-safe.

**Acceptance trace:** packet under `lab-docs/lang/` ✓; live JSON surfaces verified (§2) ✓; canonical
record/envelope chosen — bare array (CLI) + shape C (MCP) (§3,§6) ✓; severity vocabulary (§3) ✓; exit-code
conventions (§5) ✓; MCP shape C confirmed with evidence (§6) ✓; human-vs-machine boundary explicit (§7) ✓;
compatibility/migration (§8) ✓; Rust-CLI pressure assessed not over-claimed (§9) ✓; conformance test added +
next cards named (§10,§11) ✓; `git diff --check` clean.
