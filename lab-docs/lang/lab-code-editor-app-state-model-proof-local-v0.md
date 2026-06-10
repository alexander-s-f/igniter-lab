# LAB-APP-STATE-P2: Proof-Local Code-Editor App-State Model

**Track:** `lab-code-editor-app-state-model-proof-local-v0`
**Status:** CLOSED — PROOF COMPLETE (70/70)
**Route:** LAB PROOF / APP-STATE MODEL / NO KEYWORD
**Decision:** **A — metadata is enough for now** (continue proof-local conventions + documentation; hold any proposal). Smallest future candidate, held: public/internal visibility → `LAB-MODULE-SURFACE-P1`.
**Authority:** No implementation authority. No canon claim. No stable API. No runtime state-holder. No framework/app API. No new keyword.

---

## 0. What this proof did

Built a code-editor application's state model using **existing Igniter concepts only**
and verified — 70/70 — that the model compiles, runs (pure transitions on the VM), and
keeps the six P1 terms visibly separate. It then measured exactly **which parts of app
architecture the language carries as inert metadata today** and **which parts require a
proof-local sidecar** (and would, in future, require a proposal).

No parser/compiler/VM change was made or needed. `intent` (PROP-045) is **not** parseable
in the lab toolchain, so the descriptive app vocabulary is carried in a sidecar JSON
registry instead — itself a finding.

### Artifacts

| File | Role |
|------|------|
| `igniter-view-engine/fixtures/app_state/editor_app_state.ig` | 8 pure transition contracts + 11 state-value record types (VM-runnable) |
| `igniter-view-engine/fixtures/app_state/editor_app_state_durable.ig` | durable save/load: `effect` + `observed` contracts gated by `IO.StorageCapability` (compile-proof; split per the LAB-STORAGE-CAPABILITY-P2 two-fixture pattern) |
| `igniter-view-engine/fixtures/app_state/editor_app_state.registry.json` | **proof-local sidecar**: the B-route descriptive vocabulary the *language* does not carry (instance identity, holder binding, visibility, event→op→fact assembly) |
| `igniter-view-engine/proofs/verify_lab_app_state_p2.rb` | proof runner — 70 checks, 9 sections |
| `lab-docs/lang/lab-code-editor-app-state-model-proof-local-v0.md` | this document |
| `.agents/work/cards/lang/LAB-APP-STATE-P2.md` | card + gap packet |

---

## 1. The six terms, made visibly separate

| Term | In the editor model | **Where it actually lives** |
|------|--------------------|-----------------------------|
| **state-value** | `DocumentState`, `CursorState`, `SelectionState`, `ClipboardState`, `DiagnosticSet`, `EditHistory`, `BufferRef`, `EditorSnapshot` | **In-language** — typed records (`type_env`, proven present + typed). |
| **state-instance** | "buffer `a.rs`", "view #2" | **Sidecar only** — `instance_key_source` per fact. Absent from SIR. |
| **state-holder** | host process / external store | **Outside the language** — sidecar `holder_class` (`host`/`store`); the durable holder is named by the `read … from "editor.workspace"` string. No holder field in SIR. |
| **transition** | `InsertText`, `MoveCursor`, `SelectRange`, `CopySelection`, `ApplyEdit`, `RecomputeDiagnostics`, `PushHistory` | **In-language** — pure contracts `(snapshot + event) → next`, VM-verified. |
| **module-boundary** | `module Lab.Editor.AppState` | **In-language** — namespace + purity only; holds nothing (HOST checks confirm). |
| **external-capability** | `IO.StorageCapability` on save | **In-language** — capability + effect on the durable edge only; hot/session transitions carry none. |

Instance identity is **not** collapsed into the type name (`DocumentState` is reused by
`document` (session/host) and `saved_doc` (durable/store) — two facts, two instances, one
shape). The module holds no state. No capability is required for hot/session state.

---

## 2. Proof results (70/70)

| Section | n | What it proves |
|---------|---|----------------|
| APPSTATE-COMPILE | 5 | Both fixtures compile clean (Rust); Ruby TC accepts all 10 contracts, 0 type_errors |
| APPSTATE-SHAPE | 13 | 11 state-value record types present + typed; composite `EditorSnapshot.doc : DocumentState` |
| APPSTATE-LIFECYCLE | 10 | Every fact's intended lifetime rides its `output` lifecycle into SIR (`:session/:local/:window/:durable/:audit`) — the **E path** works in-language |
| APPSTATE-TRANSITION | 12 | All transitions `pure`/CORE; carry no capability/effect; VM round-trips `InsertText`/`MoveCursor`/`ApplyEdit` (nested records preserved); outputs are fresh values |
| APPSTATE-PUBLIC | 5 | Effect/observed boundary ops inferable from `modifier`; pure public-op vs pure-helper **indistinguishable in SIR** (visibility gap); sidecar classifies all |
| APPSTATE-DURABLE | 6 | Save = `effect` + `IO.StorageCapability` + bound effect; output `:durable`; load = `observed` read-from-store; **no storage execution** |
| APPSTATE-HOST | 4 | No mutable-binding keyword; outputs are record *values* not handles; hot/session need no capability; sidecar holder = host (hot/session) / store (durable) |
| APPSTATE-GAP | 8 | The four P1 gaps, each asserted **absent from SIR** *and* **present in sidecar** |
| APPSTATE-CLOSED | 7 | No `state{}`; no public/private/internal kw; no service/actor/class; no module instance; `intent` unused (unparseable); no storage exec; main CORE / durable ESCAPE |

Regressions clean (toolchain untouched): LAB-TC-ARRAY-P1 27/27, LAB-QUERY-P3 44/44.

---

## 3. The seven minimum proof questions — answered

1. **Can host-owned editor state be represented as typed records?**
   **Yes.** 11 record types (`DocumentState`…`EditorSnapshot`/`TransitionReceipt`), all
   present and typed in `type_env`; composites nest records (`EditorSnapshot.doc`).

2. **Can transitions be modeled as pure contracts from snapshot + event → next snapshot?**
   **Yes.** 7 pure CORE transitions; the VM round-trips `InsertText` (doc+event→doc),
   `MoveCursor` (cursor+event→cursor), and the composite `ApplyEdit`
   (snapshot+doc+cursor→snapshot, nested records preserved). Each output is a fresh value.

3. **Can lifecycle classes describe each fact's lifetime without creating holders?**
   **Yes — in-language.** `output next : DocumentState lifecycle :session` and friends ride
   `:local/:session/:window/:durable/:audit` straight into the SIR `output_ports[].lifecycle`.
   This is the **E path** and it works with zero new surface. The lifecycle annotation
   describes *lifetime*, not *holder* — no holder is created.

4. **Can public operations vs internal helpers be documented or inferred from current surfaces?**
   **Partially.** *Effecting/observing* boundary operations are inferable from `modifier`
   (`effect`/`observed` → ESCAPE). But a **pure public operation and a pure helper are
   indistinguishable in SIR** — `InsertText` (public) and `BuildTransitionReceipt`
   (internal) share `modifier=pure` with no visibility marker. The public/internal split is
   carried in the sidecar. **This is the cleanest, smallest language gap.**

5. **Can durable save/load be represented as an effect boundary without implementing storage?**
   **Yes.** `BuildSaveRequest` is an `effect` contract gated by `IO.StorageCapability` with
   a bound effect and `:durable` output; `LoadDocument` is an `observed` read from the named
   store. `compute` is a pure stub — **no execution, no DB, no SQL, no ORM**.

6. **Can a future agent ask "what state does this app own?" from metadata/fixtures?**
   **Yes — at two fidelities.** From **SIR alone**, an agent recovers the owned-fact set as
   `(type_tag, lifecycle)` pairs across all `output_ports` — e.g.
   `{(DocumentState,session),(CursorState,local),(DiagnosticSet,window),(SaveRequest,durable)…}`.
   From the **sidecar**, it additionally recovers instance keying, holder class, visibility,
   and event wiring. So "what state, at what lifetime" is answerable from the language;
   "owned by whom, keyed how, wired to which events, public or not" needs the sidecar.

7. **Which of the four P1 gaps remain unsolved (i.e. non-language)?**
   All four remain **non-language**, but all four are expressible as **inert sidecar
   metadata** with no holder runtime — see the gap packet. None is blocking.

---

## 4. Gap packet (concrete)

Each gap is proven **absent from SIR** and **present in the sidecar** (APPSTATE-GAP 01–08).

| # | Gap | SIR evidence (absent) | Sidecar carries | Severity / smallest fix |
|---|-----|----------------------|-----------------|-------------------------|
| G1 | **state-instance identity** | `output_ports` keys are exactly `{name, type_tag, lifecycle, required}` — no `instance/id/key/holder` field; `DocumentState` is reused for two distinct facts | `facts[].instance_key_source` (`buffer_uri`, `view_id`, `session_id`, `workspace_path`) | Medium. Identity is genuinely *host* data; arguably should stay external. Not blocking. |
| G2 | **fact↔holder binding** | no `holder`/`owner` field on any contract or port; `lifecycle` describes lifetime, not owner | `facts[].holder_class` (`host`/`store`) + `holders{}` | Medium. Partly proxied by lifecycle (`:durable`→store) + the `read … from` string; explicit binding is sidecar-only. |
| G3 | **app assembly (event→op→fact)** | no `on_event`/`wiring`/`routes` key anywhere in SIR; contracts are a flat set | `operations[].on_event` + `operations[].transitions` | Medium–high if ever first-class; this is the largest surface (Route D). Sidecar is adequate now. |
| G4 | **public/internal visibility** | no `visibility`/`access` field; pure public op and pure helper share `modifier=pure` | `operations[].visibility` (`public`/`internal`) | **Low — smallest, cleanest gap.** The natural first proposal if pressure arrives. |

**Ranking for any future proposal:** G4 (visibility) is the smallest and most self-contained
surface; G3 (assembly) is the largest and most framework-shaped (defer hardest); G1/G2 are
arguably *correctly* host-owned and may never need a language surface.

---

## 5. Decision

**Classification: A — metadata is enough for now.**

Justification, grounded in the proof:

- Everything required to **express and run** the editor state model is already in-language
  (records + pure transitions + lifecycle + capability boundary) — 70/70.
- Everything required to make the app **inspectable** is achievable today with **zero new
  language surface**: lifetimes from SIR, the rest from an inert sidecar (the same
  metadata-not-authority pattern as `intent`/`module_map`).
- **No gap is blocking.** None forces a holder, a keyword, or a runtime. Adopting a surface
  now would be the premature design-lock P1 explicitly warned against.

**Action:** continue the proof-local convention (state-value records + pure transitions +
lifecycle-annotated outputs + capability-gated durable edge + sidecar registry) and
**document it**; **hold** any proposal.

**Held candidate (only if real pressure arrives):** a focused **public/internal visibility**
surface — gap G4, the smallest — via `LAB-MODULE-SURFACE-P1`. Do **not** open it speculatively.

---

## 6. Boundary findings (evidence, not authority)

- **F1 — lifecycle is the E path, and it already works.** `:local/:session/:window/:durable/
  :audit` survive into `output_ports[].lifecycle` with no change. The B+E recommendation
  from P1 is validated for the lifetime dimension entirely in-language.
- **F2 — `intent` is not parseable in the lab toolchain.** PROP-045 is convention-only;
  the lab parser has no `intent` keyword. The descriptive app vocabulary therefore lives in
  a sidecar today. If a future agent-readable in-language purpose surface is wanted,
  PROP-045 landing (not a new keyword) is the path.
- **F3 — effect contracts force a fixture split.** The VM rejects an igapp load when an
  unbound capability passport is present, so durable (`effect`/`observed`) contracts cannot
  share a runnable igapp with the pure transitions. The two-fixture pattern (from
  LAB-STORAGE-CAPABILITY-P2) is the correct lab shape; it is also a faithful model of
  reality: hot state runs free, the durable edge requires authority.
- **F4 — `modifier` is a partial visibility signal.** It cleanly separates *effecting* from
  *pure*, but cannot separate *public pure op* from *internal pure helper*. That residue is
  the visibility gap (G4).
- **F5 — no hidden mutation appears.** Every transition returns a fresh value; the input is
  not aliased or mutated; there is no `var`/`mut`/holder construct. The honesty/debuggability
  property P1 demanded is preserved.

---

## 7. Closed surfaces (none opened)

| Surface | Status |
|---------|--------|
| `state {}` declaration / new keyword | Closed — none added (APPSTATE-CLOSED-01) |
| `public`/`private`/`internal` keyword | Closed (APPSTATE-CLOSED-02) |
| service / actor / class holder | Closed (APPSTATE-CLOSED-03) |
| module instances / module-as-holder | Closed (APPSTATE-CLOSED-04) |
| app-manifest semantics (Route D) | Closed — deferred; sidecar is descriptive only |
| storage execution / DB / SQL / ORM | Closed (APPSTATE-DURABLE-06, CLOSED-06) |
| parser / compiler / VM change | Closed — **zero implementation files touched by this card** |
| canon / stable / public / framework API | Closed — LAB-ONLY |

---

## 8. Next route

Per the decision (A): **hold implementation; document the proof-local convention** (this
doc + the registry sidecar are that documentation). 

If application pressure later demands one architecture concept become first-class, open the
**smallest** one first:

- **public/internal visibility (G4)** → `LAB-MODULE-SURFACE-P1` *(held; smallest, cleanest)*
- fact↔holder binding (G2) → `LAB-APP-STATE-P3` *(only if host-keyed binding proves insufficient)*
- app assembly / event→op→fact (G3) → `LAB-APP-ASSEMBLY-P1` *(largest; defer hardest)*

Until then: **hold**, and use the convention proven here.

---

## Depends on

| Card | Used for |
|------|----------|
| LAB-APP-STATE-P1 | design boundary, six-term model, B+E recommendation |
| LAB-QUERY-P3 | record shapes; pure-value-in-source pattern |
| LAB-STORAGE-CAPABILITY-P2 | effect/capability boundary; denial-as-data; two-fixture pattern |
| LAB-RECORD-VM-P3 | nested record VM round-trip (composite `ApplyEdit`) |
| PROP-031 / Ch10 | contract modifiers (`pure`/`observed`/`effect`) |
| PROP-035 / Ch12 | effect surface / capability / external boundary |
| PROP-045 | intent precedent (and its non-availability — F2) |
| Ch2 | lifecycle vocabulary (the E path) |

---

*LAB-ONLY. Proof-local. No implementation authority. No canon claim. No stable API. No runtime state-holder. No new keyword.*
