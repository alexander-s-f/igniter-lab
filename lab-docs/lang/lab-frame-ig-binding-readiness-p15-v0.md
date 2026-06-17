# lab-frame-ig-binding-readiness-p15-v0 — binding a ViewArtifact to real `.ig`

**Card:** `LAB-FRAME-IG-BINDING-READINESS-P15` (readiness/design — NO code, NO parser/runtime)
**Status:** CLOSED — defines how a ViewArtifact's `bind`/`action` map to real `.ig` data and effects
BEFORE any implementation, without turning `.ig` into UI markup or giving the UI hidden authority.
Lab-only, not canon.

The one-line thesis: **the binding is the JOIN of the two Igniter contours.** The UI is the
fact-to-frame contour (`state → frame → input → intent → state`); `.ig`+machine is the wire-to-effect
contour (`request → passport → contract → effect → receipt`). A bound action is a UI intent that the
**host** runs through wire-to-effect and whose result/receipt comes back as a new view-state fact.
The browser never crosses that boundary.

## 1. Current state (verified against live code)

- **P12 implements** `ViewArtifact JSON → igniter-ui-kit tree → FrameRuntime`, byte-identical to the
  hand-written constructor (`view_artifact::compile` → `Workbench`/`Form`).
- **Keys that exist today, resolved LOCALLY:**
  - `data.leads` (inline array) — the sidebar list data; today it is literal JSON, not a `.ig` read.
  - `regions.sidebar.bind: "leads"` / `on_select: "select"` — `bind` is decorative today; `on_select`
    maps to the local `select` reducer action.
  - `regions.main.submit.action: "submit"` — resolves to the local `workbench_reducer` `submit` arm
    (local validation writes an `err:<lead>` fact).
- **Not implemented:** any read from a `.ig` contract, any invoke of a `.ig` contract/effect, any
  host authority, any receipt. `bind`/`action` are a SEAM.
- **The real `.ig`/machine execution surface exists** (igniter-machine, machine-free of the UI):
  `ContractRegistry { contracts: HashMap<String, Value> }` (named, declared contracts; `register` /
  `get`), `CoordinationHub::invoke(passport: &CapabilityPassport, pool_id, …) -> Result<Value,
  PoolRefusal>` (passport-authorized invoke against a signed `ServiceRecipe { capsule_digest,
  entry_contract, pool_sizing, … }`), and the effect path `run_write_effect` / `ingress::handle_effect`
  producing capability-IO receipts. These are the host-side primitives a bridge would target — they
  are NOT in the UI/browser path.

## 2. Binding taxonomy

Five declared binding classes. Each is a NAMED entry in the artifact, resolved by the host — never an
arbitrary string executed by the view.

| class | view side | host side |
|---|---|---|
| **data bind** | a region/list declares `bind: <source>` | host reads `sources.<source>` → a `.ig` read contract (or a host-provided snapshot) → a data fact handed to the view |
| **selection bind** | view-local: `__selection__` picks a key from bound data | host does nothing; selection never leaves the view |
| **validation bind** | a field/form declares `validate: <contract>` (optional) | host runs the declared `.ig` validation contract; result → scoped view errors. If absent, local validation (P10) stands |
| **action bind** | a button/intent declares `action: <name>` resolving to `actions.<name>` | host resolves `actions.<name>.contract` in the `ContractRegistry` and invokes it under a passport |
| **effect bind** | `actions.<name>.effect` declared | the invoked contract's declared effect runs via capability-IO → a receipt; the receipt id returns to the view |

Hard rule: an action/source is callable **only if** it is (a) declared in the artifact's
`sources`/`actions` AND (b) registered in the host's `ContractRegistry`. Double gate. No `bind`/
`action` string reaches an executor without passing both.

## 3. State ownership model

```text
view-local state    __focus__, __selection__, field drafts (fld:*), scoped errors err:<scope>
  (FrameRuntime)    — owned by the UI reducer; never authoritative; replayable; lives in the frame world.

domain state        .ig data / contracts / facts (e.g. the real lead list, persisted lead records)
  (.ig + machine)   — owned by .ig; read via a data-bind contract; mutated only via an action/effect.

effect receipts     capability-IO receipts (idempotency key, status, correlation) in the machine
  (machine)         — the audit truth of what actually happened. The view sees only an id/status.

derived state       the inspector / frame projection — a pure function of (view-local ∪ bound data).
  (projector)       — never stored; recomputed each frame.
```

The crucial separations: a **field draft is not a domain fact** (typing `priority="P1"` mutates a
view-local `fld:Ada:priority`, NOT a `.ig` record — that only happens on a bound submit action); a
**view `err:<lead>` is not an `.ig` diagnostic** (local errors are UI hints; a validation-bind result
is a domain diagnostic mapped INTO scoped view errors).

## 4. Execution and authority model

```text
UI (browser)                 HOST (trusted boundary)                  .ig + machine
────────────                 ─────────────────────                    ─────────────
action intent  ──request──▶  resolve actions.<name> in artifact
(payload = view  (no auth)   + ContractRegistry.get(contract)         (refuse if either missing)
 drafts/selection)           │
                             ├─ build input from declared template     ($selection.lead, $form.values)
                             ├─ CoordinationHub.invoke(passport, pool) ─▶ capsule activation
                             │   (HOST holds the passport)                entry_contract dispatch
                             ├─ declared effect → run_write_effect    ─▶ capability-IO → RECEIPT
                             ◀─ result Value + receipt id ────────────────┘
 new view-state fact ◀─push─ map result → data refresh / __action__ fact / scoped errors
 re-project frame
```

- **Who calls what:** only the host calls `.ig`. The browser emits a declared action *request*
  carrying a view payload; it holds no passport, no capability, no secret. The host owns authority,
  resolution, execution, receipts, and failure handling.
- **Resolution:** `actions.<name>.contract` → `ContractRegistry.get(name)` (must exist) →
  `invoke(passport, production_pool)` against a signed `ServiceRecipe`. The passport scope must
  permit the contract (the existing `authed(passport, "invoke")` + recipe gate).
- **Failure representation:** view-local validation → `err:<scope>` facts; `.ig` validation-bind →
  domain diagnostics mapped into `err:<scope>`; authority/effect refusal → a `PoolRefusal` surfaced as
  a non-crashing view error + (optionally) a console-visible status; effect outcomes → receipts.
- **v0 execution style: request/receipt (async at the host boundary).** A bound action becomes a
  pending request; the host executes; the result returns and is applied as a new frame (same
  `input → effect → frame` discipline as a local intent — just the effect is a host round-trip).
  Synchronous fixtures are allowed in proof-local tests; real effects are async/receipt.

## 5. Artifact shape proposal (design sketch — not implemented)

Extend ViewArtifact with top-level `sources` + `actions` (the binding manifest). `bind`/`action` keys
reference entries by name; `$…` placeholders reference view-local state, resolved by the host.

```json
{
  "artifact": "view", "version": 0, "layout": "workbench",
  "sources": {
    "leads":         { "contract": "ListLeads", "mode": "read" }
  },
  "actions": {
    "submit_lead":   { "contract": "SubmitLeadReview",
                       "input":  { "lead": "$selection.lead", "fields": "$form.values" },
                       "validate": "ValidateLeadReview",
                       "effect": "declared" }
  },
  "regions": {
    "sidebar":   { "component": "List", "bind": "leads", "on_select": "select" },
    "main":      { "component": "Form", "for_each": "selected",
                   "fields": [ /* … */ ],
                   "submit": { "label": "Submit", "action": "submit_lead" } },
    "inspector": { "component": "KeyValuePanel", "bind": "selected" }
  }
}
```

- `bind: "leads"` → `sources.leads` → a `.ig` read; the result populates the list (replacing today's
  inline `data.leads`).
- `submit.action: "submit_lead"` → `actions.submit_lead`; `input` is a declared template over
  view-local state; `validate` (optional) delegates validation; `effect: "declared"` means the
  contract's own effect declaration governs whether a receipt-producing effect runs.

## 6. Minimal example — lead-review, end to end (design level)

1. **load:** host reads `sources.leads` via `ListLeads` → `["Ada","Grace","Linus"]` → sidebar list.
2. **selection:** clicking a lead sets `__selection__` (view-local; no host call).
3. **drafts:** typing priority / cycling stage / toggling hot mutate `fld:<lead>:*` (view-local).
4. **submit:** clicking Submit emits action `submit_lead` with payload `{lead: $selection.lead,
   fields: $form.values}`.
5. **host:** resolves `SubmitLeadReview` in the registry → (optional) runs `ValidateLeadReview`:
   - invalid → domain diagnostics mapped to `err:<lead>` (scoped, replayable) → no effect;
   - valid → `invoke(passport, pool)` → declared effect via capability-IO → receipt.
6. **result:** the receipt id + any returned data push back as a new frame (e.g. a `__submitted__`
   fact or a refreshed lead record); the inspector derives from selected data + drafts; the console
   shows the action in lineage with its receipt id.

Selection and drafts stay view-local throughout; only `submit` crosses to `.ig`; errors are scoped
and replayable; the browser holds no authority.

## 7. Diagnostics and failure modes

| failure | where surfaced | behavior |
|---|---|---|
| missing source binding (`bind` name not in `sources`) | compile-time (host) | refuse to bind; artifact error (like P12 `ViewError::Schema`) |
| unknown contract/action (not in `ContractRegistry`) | host resolution | refuse; non-crashing view error; nothing invoked |
| type mismatch (view payload vs `.ig` input contract) | host, pre-invoke | reject; diagnostic; no invoke |
| validation failure (`validate` contract) | host → view | map domain diagnostics → `err:<scope>`; no effect |
| effect denied (passport/capability refusal) | host (`PoolRefusal`) | surface as a view error + console status; no effect; no crash |
| effect unknown / retryable | machine receipt | receipt `pending`/retry; view shows in-flight; idempotent on replay |
| stale binding (artifact/schema drift) | host version check | refuse with a clear "binding stale vs registry" diagnostic |

## 8. Security / authority guardrails

- **No arbitrary dynamic string dispatch.** A callable contract must be declared in the artifact
  (`sources`/`actions`) AND registered in the host `ContractRegistry`. The view cannot name an
  unlisted contract.
- **Browser/WASM is authority-free.** No passport, no capability, no secret in the browser; it emits
  requests only. Passports/secrets live host-side (the existing `secrets` provider + signed-passport
  surfaces).
- **Effects go through capability-IO**, not the UI reducer. The reducer never executes an effect; it
  emits an action request; the host runs `run_write_effect` and owns the receipt.
- **`igniter-machine` stays out of the UI/browser/core path.** The bridge is a host-side adapter; the
  browser talks to it over a request boundary, never linking the machine.
- **Redaction.** Any data shown in the console/lineage (which is a developer tool) must redact
  secrets/PII; receipts expose ids/status, not secret payloads. The console must not become a data
  exfiltration surface.

## 9. What NOT to implement yet

- No `.igv`. No parser/compiler changes. No new stable public API claim.
- No live SparkCRM / external IO (real effects stay behind the human-gated machine live gate).
- No `igniter-machine` dependency in the UI-kit browser/core path.
- No widening of the machine's dynamic-dispatch policy.

## 10. Next implementation route

**`LAB-FRAME-IG-BINDING-P16`** (narrow, proof-local — named, NOT started):

```text
ViewArtifact with ONE source + ONE action
  → proof-local host binding adapter (Rust): resolve sources/actions against a FAKE/fixture
    ContractRegistry (no real machine, no external IO)
  → ListLeads fixture returns a deterministic lead list (data bind)
  → SubmitLeadReview fixture returns a deterministic receipt-like record (action + effect bind),
    with one validation path → scoped view errors
  → result applied as a new frame; console shows the action + receipt id in lineage
```

Guardrails for P16: local + deterministic + authority-explicit; the browser path stays machine-free
and authority-free (a fixture host adapter, not the real machine); real `CoordinationHub`/passport
execution is a SEPARATE later gate, not P16. External effects and `.igv` remain later gates.

## Result (for the card)

ViewArtifact `bind`/`action` map to `.ig` as a declared-only, host-resolved, passport-authorized
request/receipt bridge — the join of the fact-to-frame and wire-to-effect contours. View-local state
(focus/selection/drafts/scoped errors) is separated from domain state (`.ig` data/contracts) and from
effect receipts (machine). No arbitrary dispatch; the browser is authority-free; effects go through
capability-IO. Concrete `sources`/`actions` JSON sketch + the lead-review example provided. Next:
`LAB-FRAME-IG-BINDING-P16` (one source + one action, fixture host, deterministic) — not started.
