# lab-igniter-projection-dialects-p0-v0 — naming & governing `.ig*` authoring dialects

**Card:** `LAB-IGNITER-PROJECTION-DIALECTS-P0` · **Delegation:** `OPUS-PROJECTION-DIALECTS-A`
**Status:** READINESS / ARCHITECTURE BOUNDARY (v0) — names the `.ig*` phenomenon as **Projection
Dialects** and defines the governance contract before it drifts. **No implementation, no CLI, no
compiler/VM/UI/server change, no canon promotion, no `.igv`/`.igweb` edits.**
**Authority:** Lab readiness. Grounded in the two live dialects (`igniter-ui-kit/src/igv.rs`,
`igniter-compiler/src/igweb.rs`).

---

## 1. Executive summary

Two `.ig*` authoring surfaces now exist — `.igv` (UI sugar → ViewArtifact JSON) and `.igweb` (routing
sugar → generated `.ig` `Serve`). They are useful but slippery: if every domain invents a bespoke
`.igfoo` with hidden runtime meaning, product/app semantics leak into the public language. This packet
names the pattern **Projection Dialect**, defines what it is (and is not), a doc-level registry schema,
the MUST/SHOULD invariants, classifies both live dialects (neither becomes canon), permits **app-local**
dialects under bounds, sketches future tooling (no code), and gives an anti-proliferation smell test +
a promotion ladder. The load-bearing rule: **a Projection Dialect deterministically lowers into an
existing, inspectable canonical artifact and creates NO hidden runtime authority.**

## 2. Definition and non-definition (Q1)

**Term: Projection Dialect** (short: *dialect*). Affirmed — it conveys that `.ig*` files are a
*projection of* canonical artifacts (`.ig`, ViewArtifact JSON), not independent runtimes. (Rejected
alternatives: "Lowering Dialect" — too mechanical; "Authoring Dialect" — doesn't convey the
no-independent-existence constraint; "Sub-language" — wrongly implies a runtime.)

> **A Projection Dialect is an authoring syntax that deterministically lowers into an existing
> canonical Igniter artifact. It may improve authoring ergonomics; it may not create hidden runtime
> authority.**

**It is NOT:**
- a new runtime or execution semantics (it produces an existing artifact and stops);
- canonical `.ig` language (lab evidence ≠ canon; §10);
- a place for product/domain/vendor semantics in the public language;
- a route table, effect authority, or IO surface;
- a dynamic-dispatch escape hatch (the target's static discipline is preserved).

```text
.ig     → canonical executable contract language (the ONLY runtime authority)
.igv    → Projection Dialect → ViewArtifact JSON / frame artifact
.igweb  → Projection Dialect → generated .ig Serve(Request)->Decision
.ig*    → app/local dialect  → a REGISTERED lowering target, never implicit canon
```

## 3. Registry schema (Q3) — doc-level, not code

A dialect is described by one registry entry (a documentation record in v0; a tool config later, §8):

```text
dialect_id:                  stable id (e.g. "igv", "igweb")
extension:                   file extension (.igv, .igweb)
owner:                       who owns it — "igniter-lab" | "<app/org>"  (app-local allowed; not public canon)
status:                      private | lab | experimental | canon-candidate | canon   (§10)
input_kind:                  the dialect's own surface (line-oriented text, etc.)
target_kind:                 the canonical artifact it lowers to (".ig source" | "ViewArtifact JSON" | "manifest JSON")
lowerer:                     the pure function/tool (e.g. lower_igv, lower_igweb)
deterministic:               true (MUST) — same input → byte-identical output
source_map:                  line | full | none   (line MUST where errors can point back)
generated_artifact_policy:   inspectable; committed-or-temp; "generated, do not hand-edit"
runtime_authority:           none (MUST) — no IO/effects/secrets/passport introduced by the dialect
closed_surfaces:             what the dialect must NOT do (server routing, dynamic dispatch, domain leak…)
test_obligations:            determinism + lowered-artifact-compiles/equivalence + diagnostic position
```

`owner` is explicit: **app-local dialects are allowed**, but ownership by an app/org does NOT make the
dialect part of public Igniter — that requires a separate canon gate (§10).

## 4. Invariant checklist (Q4)

Every `.ig*` dialect MUST:
- **Determinism (MUST):** same input → byte-identical lowered artifact. (`.igv`: serde sorted-key JSON;
  `.igweb`: ordered route emission.)
- **Inspectable target (MUST):** the lowered artifact is a known, readable canonical artifact a human
  can open and a tool can re-compile/validate.
- **No hidden runtime authority (MUST):** the dialect introduces no IO, effects, secrets, passport, or
  network; any effect is named as data in the *target* and authorized by the host, not the dialect.
- **No dynamic dispatch beyond the target (MUST):** if the canonical target has no dynamic dispatch
  (Igniter `.ig` has none — `call_contract` is a compile-time literal), the dialect must not synthesize
  one.
- **No server-core / domain leakage (MUST):** lowering lives in lab tooling, never in `igniter-server`;
  product vocabulary stays in app code, not the dialect mechanism.
- **Lowered-artifact equivalence/validity tested (MUST):** prove the lowered artifact compiles
  (`.igweb`) or is byte-identical to the hand-written canonical form (`.igv`).
- **Stable, line-positioned diagnostics (MUST where feasible):** malformed input → an error carrying a
  line (both dialects do: `IgvError{line,msg}`, `IgwebError{line,message}`).

SHOULD (not MUST), with rationale:
- **Full source map (SHOULD):** a generated-line → source-line map is ideal so a *downstream* compiler
  error on generated `.ig` points back to the `.igweb` line. Today only the lowering's own diagnostics
  are line-positioned; a full source map is desirable but not yet required (the multifile source-map
  facility exists for `.ig`, `LAB-COMPILER-MULTIFILE-SOURCE-MAP-P3`, and could be extended). Marked
  SHOULD because the lowered `.ig` is committed and inspectable, so a downstream error is already
  traceable by reading it.

## 5. `.igv` registry entry (Q5)

```text
dialect_id:                igv
extension:                 .igv
owner:                     igniter-lab (frame/ui-kit)
status:                    lab
input_kind:                line-oriented UI/view authoring text
target_kind:               ViewArtifact JSON (serde_json::Value)
lowerer:                   igniter-ui-kit/src/igv.rs :: lower_igv(src) -> Result<Value, IgvError>
deterministic:             true (serde default Map = sorted keys; arrays keep order → byte-identical JSON)
source_map:                line (IgvError{line,msg})
generated_artifact_policy: ViewArtifact JSON consumed by existing view_artifact / binding / bridge; byte-identical to hand-written
runtime_authority:         none — browser/UI path is machine-free; no passport/secret/effect in the dialect
closed_surfaces:           no machine in the UI path; not canon `.ig`; no domain semantics
test_obligations:          determinism + byte-identical-vs-hand-written ViewArtifact (proven, LAB-FRAME-IGV-BINDING-SYNTAX-P1)
```
Acceptable as projection sugar because it adds zero semantics: it is a typographic shortcut for a
ViewArtifact JSON that already exists and is independently consumed, machine-free.

## 6. `.igweb` registry entry (Q6)

```text
dialect_id:                igweb
extension:                 .igweb
owner:                     igniter-lab (compiler tooling)
status:                    lab
input_kind:                line-oriented route authoring (`app … entry … { route METHOD "pat" -> Contract [requires idempotency] }`)
target_kind:               generated .ig source — module AppRoutes, pure contract Serve(Request) -> Decision
lowerer:                   igniter-compiler/src/igweb.rs :: lower_igweb(src) -> Result<String, IgwebError>
deterministic:             true (routes keep source order; patterns grouped first-seen; no map iteration)
source_map:                line (IgwebError{line,message}); generated .ig is committed/inspectable (full source map = SHOULD)
generated_artifact_policy: generated .ig, "do not hand-edit"; compiles through real multifile (proven, no OOF-RE1/OOF-TY0)
runtime_authority:         none — route targets are STATIC call_contract("Literal", …); params via stdlib.regexp; effect authority stays host-owned (Decision names a logical target only)
closed_surfaces:           no server-core route table; no dynamic dispatch; no domain app in igniter-server; no DB/live
test_obligations:          determinism + line diagnostics + generated project compiles + static-call/regexp-param shape (proven, LAB-IGNITER-WEB-ROUTING-LOWERING-P4)
```
**P4 proceeds unchanged** — it is the FIRST `.igweb` dialect implementation. Its proof doc/card should
carry a thin pointer to this packet (see closing report); P0 does not rewrite or block P4.

## 7. Custom / app-local dialect policy (Q7)

App-local and third-party dialects are **allowed**, e.g.:
```text
acme.workflow → acme.workflow.igworkflow → generated .ig
spark.callrail → spark.callrail.igroute  → app-local .ig or manifest JSON
```
Rules (bounded freedom):
- **app-local by default** — `owner` ≠ `igniter-lab`; lives in the app's repo/tooling.
- **no public canon claim** — being app-local (or popular) never makes it Igniter language (§10).
- **no extension collision** — two owners must not both claim `.igroute` without a registry decision;
  prefer namespaced ids (`acme.igworkflow`).
- **explicit lowerer** — the lowering tool must be named in project/tool config (§8), never an implicit
  magic step.
- **reviewable generated artifact** — the lowered `.ig`/JSON is committed/inspectable; reviewers read
  the artifact, not just the sugar.
- **same invariants (§4)** apply — a custom dialect that introduces hidden authority is rejected.

## 8. Future tooling sketch (Q8) — readiness only, NO CLI implemented

```bash
igniter dialect list                                   # show registered dialects + status
igniter dialect lower routes.igweb --out gen/routes.ig # run the registered lowerer
igniter dialect check routes.igweb                     # parse + lower + (for .ig targets) compile-check
```
or declarative project config:
```toml
[[dialects]]
id      = "igweb"
inputs  = ["routes/**/*.igweb"]
target  = "generated/routes.ig"
tool    = "igniter-web-lower"
status  = "lab"
```
This is a sketch to anchor the registry shape; **no CLI/config is built in this card** (a future
`LAB-IGNITER-DIALECT-REGISTRY-P1` would, only once ≥2 dialects need tooling).

## 9. Anti-proliferation / rejection rules (Q9)

Smell test — a new `.ig*` is justified ONLY if ALL hold:
1. it lowers to an **existing** canonical target (no new runtime);
2. the target artifact is **inspectable**;
3. it introduces **no hidden authority** (IO/effects/secrets/dispatch);
4. it **reduces boilerplate without adding semantics**;
5. it is **app-local by default** (not public canon);
6. it could **not** simply be a normal `.ig` **library/contract** instead.

**Do NOT create a dialect when:** the need is real logic (write a contract/library); the sugar would
encode product/domain semantics (that belongs in app `.ig`, not the language); it would need a new
runtime/dispatch/IO; a plain `.ig` helper or the existing `.igweb`/`.igv` already covers it; or it
exists only to look novel. When in doubt → a contract/library, not a dialect.

## 10. Relationship to canon (Q10)

Promotion ladder:
```text
private → lab → experimental → canon-candidate → canon
```
- **private:** an app/org's internal dialect, unshared.
- **lab:** proven in-lab (both `.igv` and `.igweb` are here — implemented, tested, lab-only).
- **experimental:** shared for trial across lab consumers; still no canon authority.
- **canon-candidate:** formally proposed for the language with a gate packet.
- **canon:** part of public Igniter — requires an explicit `LANG-*` canon gate decision, never automatic.

**Lab evidence is NOT canon.** A dialect becoming popular (or implemented + green) does not make it part
of the Igniter language. `.igv` and `.igweb` are **lab**; promotion is a separate, deliberate decision.

---

## Next cards

1. **Pointers (this card, optional/low-noise):** add a thin "see Projection Dialects (P0)" pointer from
   the `.igweb` P4 proof doc and the `.igv` proof doc. (Applied — see closing report.)
2. `LAB-IGNITER-DIALECT-REGISTRY-P1` — implement a lab `igniter dialect list/lower/check` registry +
   command, **only** after ≥2 dialects actually need shared tooling.
3. Continue IgWeb routing under this contract (e.g. `LAB-IGNITER-WEB-ROUTING-ADAPTER-P5`) as the first
   dialect's downstream work — NOT as a special language fork.

*Readiness/architecture only. Compiled 2026-06-18; grounded in `igv.rs` + `igweb.rs`. No code change.*
