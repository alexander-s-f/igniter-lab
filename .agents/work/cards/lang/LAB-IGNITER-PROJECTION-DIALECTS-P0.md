# Card: LAB-IGNITER-PROJECTION-DIALECTS-P0 — name and govern `.ig*` authoring dialects

**Lane:** standard / readiness + architecture boundary
**Skill:** idd-agent-protocol
**Status:** OPEN
**Date opened:** 2026-06-18
**Delegation label:** OPUS-PROJECTION-DIALECTS-A
**Authority:** Lab readiness only. This card names and documents the `.ig*` phenomenon as a general
projection/lowering mechanism. It does **not** implement a new compiler feature, does **not** canonize
`.igweb`, and does **not** stop or rewrite the already-running `LAB-IGNITER-WEB-ROUTING-LOWERING-P4`
implementation.

## Why this card exists

We now have at least two `.ig*` authoring surfaces:

- `.igv` — UI/view authoring sugar that lowers to ViewArtifact JSON.
- `.igweb` — routing authoring sugar that lowers to explicit `.ig` `Serve(Request)->Decision`.

This is useful, but slippery. If every domain invents a bespoke `.igfoo` with hidden runtime meaning,
we will end up with `.igweb-spark-super-edition` and accidentally smuggle app/product semantics into
the public language.

This card gives the pattern a name and a governance contract before it drifts.

## Proposed name

**Igniter Projection Dialects**

Short form: **Projection Dialects**.

Definition:

> A Projection Dialect is an authoring syntax that deterministically lowers into an existing
> canonical Igniter artifact. It may improve authoring ergonomics, but it may not create hidden runtime
> authority.

Examples:

```text
.ig      -> canonical executable contract language
.igv     -> Projection Dialect -> ViewArtifact JSON / frame artifact
.igweb   -> Projection Dialect -> generated .ig Serve contract
.ig*     -> app/local dialect -> registered lowering target, never implicit canon
```

## Read first (verify-first, live code wins)

- `.agents/work/cards/lang/LAB-IGNITER-WEB-ROUTING-LOWERING-P4.md`
- `lab-docs/lang/lab-igniter-web-routing-lowering-p4-v0.md` if present
- `igniter-compiler/src/igweb.rs` if present
- `igniter-ui-kit/src/igv.rs` and `lab-docs/lang/lab-frame-igv-binding-syntax-p1-v0.md`
- `lab-docs/lang/lab-igniter-web-routing-dx-shape-p2-v0.md`
- `lab-docs/lang/lab-stdlib-regexp-p3-v0.md`
- Any current implemented-surface/status file that mentions `.igv` or `.igweb`

Important: P4 may already be implemented in the dirty tree. Do **not** block it. Treat P0 as a
parallel architecture packet that names the pattern and defines the registry contract P4 can later
point to.

## Goal

Write a readiness packet that defines:

1. what a Projection Dialect is;
2. what it is not;
3. how dialects are registered;
4. what invariants every `.ig*` dialect must satisfy;
5. how `.igv` and `.igweb` fit the model;
6. how app-local/user-defined dialects can exist without becoming public Igniter canon.

## Required deliverable

Write:

`lab-docs/lang/lab-igniter-projection-dialects-p0-v0.md`

Then update this card with a closing report.

Optional, only if low-noise and clearly helpful:

- add one pointer from the P4 `.igweb` proof doc/card to this P0 packet;
- add one pointer from the `.igv` proof doc/card to this P0 packet;
- do **not** rewrite old docs broadly.

## Questions to answer

### Q1 — Name and boundary

Is **Projection Dialects** the right term? If not, propose a better one. The term must make clear that
`.ig*` files are **authoring/lowering surfaces**, not independent runtime languages.

### Q2 — Canonical targets

List allowed lowering targets for v0:

- `.ig` source;
- ViewArtifact JSON;
- generated manifest JSON;
- maybe future capsule metadata.

State the rule: a dialect must lower to an already-known, inspectable target. It cannot introduce a
hidden runtime.

### Q3 — Registry shape

Design a minimal registry entry. It can be a doc-level schema for now, not code:

```text
dialect_id:
extension:
owner:
status: private | lab | experimental | canon-candidate | canon
input_kind:
target_kind:
lowerer:
deterministic:
source_map:
generated_artifact_policy:
runtime_authority:
closed_surfaces:
test_obligations:
```

Be explicit about `owner`: app-local dialects are allowed, but they do not become public Igniter
without a separate gate.

### Q4 — Required invariants

Every dialect must satisfy:

- deterministic lowering for the same input;
- stable diagnostics with source positions where possible;
- generated artifact inspectable;
- source map or at least line mapping if generated errors can point back;
- no hidden IO/effects/secrets/authority;
- no dynamic dispatch unless the target already supports it explicitly;
- no server-core/domain leakage;
- target artifact tests prove equivalence.

If any invariant should be SHOULD rather than MUST, explain why.

### Q5 — `.igv` classification

Classify `.igv` under the registry:

- target = ViewArtifact JSON;
- browser/UI path machine-free;
- runtime authority = none;
- generated artifact / snapshot policy;
- why it is acceptable as projection sugar.

### Q6 — `.igweb` classification

Classify `.igweb` under the registry:

- target = generated `.ig` `Serve(Request)->Decision`;
- route targets static;
- params lowered through `stdlib.regexp`;
- server-core routing forbidden;
- runtime authority = none; host effect authority remains outside app dialect.

Also state that P4 can proceed, but after P0 its doc/card should point to the Projection Dialects
model.

### Q7 — App-local/custom dialects

Define how third-party/user dialects can exist safely:

```text
acme.workflow.igworkflow -> generated .ig
spark.callrail.igroute   -> app-local .ig or manifest
```

Rules:

- app-local by default;
- no public canon claim;
- no extension collision without registry decision;
- lowerer must be explicit in project/tool config;
- generated artifact must be reviewable.

### Q8 — Tooling model

Sketch a possible future CLI/project config without implementing it:

```bash
igniter dialect list
igniter dialect lower routes.igweb --out generated/routes.ig
igniter dialect check routes.igweb
```

or:

```toml
[[dialects]]
id = "igweb"
inputs = ["routes/**/*.igweb"]
target = "generated/routes.ig"
tool = "igniter-web-lower"
```

This is readiness only. Do not implement CLI.

### Q9 — Anti-proliferation rule

Define the smell test for rejecting new `.ig*` surfaces:

- Does it lower to an existing target?
- Is the target artifact inspectable?
- Does it avoid hidden authority?
- Does it reduce boilerplate without adding semantics?
- Is it app-local rather than public by default?
- Could this just be a library/contract instead?

State when **not** to create a dialect.

### Q10 — Relationship to canon

Define promotion stages:

```text
private -> lab -> experimental -> canon-candidate -> canon
```

or a better minimal ladder.

Make clear: lab evidence is not canon. A dialect becoming popular does not automatically make it part
of Igniter language.

## Required output sections

The packet should include:

1. Executive summary.
2. Definition and non-definition.
3. Registry schema.
4. Invariant checklist.
5. `.igv` registry entry.
6. `.igweb` registry entry.
7. Custom/app-local dialect policy.
8. Future tooling sketch.
9. Anti-proliferation / rejection rules.
10. Next cards.

## Acceptance

- [ ] The pattern is named clearly.
- [ ] The distinction `.ig` canonical language vs `.ig*` projection dialects is explicit.
- [ ] `.igv` and `.igweb` are both classified without making either canon.
- [ ] Registry entry shape is specified.
- [ ] Custom/user/app-local dialects are allowed but bounded.
- [ ] Hidden runtime authority is forbidden.
- [ ] Tooling sketch exists but no CLI/code is implemented.
- [ ] P4 is not blocked or rewritten; it is positioned as the first `.igweb` dialect implementation.
- [ ] No `igniter-server`, compiler, VM, or UI code is changed by this card.
- [ ] Closing report includes exact files touched.

## Closed surfaces

- No implementation.
- No CLI.
- No compiler/parser change.
- No `.igweb` implementation edits.
- No `.igv` implementation edits.
- No canon promotion.
- No public extension registry runtime.
- No server-core route table.
- No SparkCRM/domain-specific dialect.

## Next after success

Likely follow-ups:

1. Add a thin pointer from `LAB-IGNITER-WEB-ROUTING-LOWERING-P4` proof docs to the Projection Dialects
   packet.
2. If useful later: `LAB-IGNITER-DIALECT-REGISTRY-P1` — implementation of a lab registry/check command,
   only after at least two dialects need tooling.
3. Continue IgWeb routing work under the projection-dialect contract, not as a special language fork.

