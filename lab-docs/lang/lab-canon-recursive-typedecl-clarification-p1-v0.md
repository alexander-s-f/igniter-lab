# lab-canon-recursive-typedecl-clarification-p1-v0

Card: `LAB-CANON-RECURSIVE-TYPEDECL-CLARIFICATION-P1`
Route: standard / canon clarification · Skill: idd-agent-protocol
Status: clarification packet (no lab change; no canon authority claimed; no spec rewrite)
Date: 2026-06-25

> **Authority boundary.** Lab clarification only. **Lab evidence does NOT change canon authority** — this
> packet surfaces canon's position (or silence), probes lab behavior, and proposes a canon-facing question.
> Resolving recursive `TypeDecl` policy is a **canon PROP decision**, not a lab call.
>
> **Path note:** the card lists canon at `/Users/alex/dev/projects/igniter`, but that directory holds only
> `docs/{research,current-waves}` — **no Covenant, no `ch13`**. The live canon spec (Covenant, Ch13, Ch2)
> is at **`/Users/alex/dev/projects/igniter-workspace/igniter-lang`** (workspace-defined canon repo); all
> canon citations below are from there.

---

## Headline

**Two axes, perpetually conflated — and the empirical probe settles which is open:**

- **Computation recursion** (self-call / loop): canon **LAW**, settled and enforced. No free recursion;
  managed repetition only. The lab gates it (free self-recursion → `OOF-TY0`, "use `recur()`").
- **Data-shape recursion** (`type Node { children : Collection[Node] }`): canon is **SILENT** — and the lab
  **already accepts it**. A recursive record type *parses, typechecks, and constructs* today (probed below,
  `status: ok`); only *traversing* it by self-call is closed.

**Recommendation: C now → B as the canon direction.** Adopt **C** as the de-facto v0 posture (already true:
`.ig` may declare + finitely construct recursive descriptors; the host projector traverses with a depth
bound) — it needs **no lab change** and exactly fits ViewArtifact/HTML. Ask canon to ratify **B** (a
recursive `TypeDecl` is allowed, but any *traversal* must be managed structural recursion / a bounded host
walker) so data recursion inherits the same "declared, bounded, auditable" law as computation recursion,
replacing today's silence.

---

## 1. The two axes (explicit)

```text
recursion-as-computation : a contract/def repeats or calls itself        → "how do I loop / recurse a walk?"
recursion-as-data-shape  : a type refers to itself (tree / AST / view)   → "can a value contain values of its own type?"
```

These are independent. You can have data-shape recursion (a tree value) with **zero** computation recursion
(a host, or a finite `map`, walks it). Conflating them is why "recursion" keeps resurfacing — the HTML/view
discussions hit the **data** axis, while Ch13 ("Managed Recursion") governs the **computation** axis.

---

## 2. Canon evidence — computation recursion is LAW (Q1 first half, Q3)

- **Covenant (bedrock, not deferred):** *"Every repetition belongs to a loop class with a compiler-verified
  contract: finite by collection size, finite by structural variant, finite by fuel, convergent by metric, or
  alive by liveness. **There is no general recursion and no unbounded loop.**"* + *"A loop is a contract over
  state transition. **It must be declared, not assumed.**"*
  (`igniter-lang/docs/language-covenant.md:135-138, 473`).
- **Ch13 Managed Recursion (Stage-4 deferred, PROP-039 experiment-pass):** five loop classes
  (Finite / Structural / FuelBounded / Convergent / Service); **`recur()` is "not a self-call… a compiler
  primitive"** with a `decreases` variant (`igniter-lang/docs/spec/ch13-managed-recursion.md:21-24, 99-123`);
  OOF-R1..R7 termination gates (`§13.7`).
- **`def` is non-recursive:** *"Non-recursive (self-reference is **OOF-F1**)… Inlined at the call site"*
  (`igniter-lang/docs/spec/ch2-source-surface.md:295-298, 343`).

**Q3 answer:** Ch13 governs **computation** (traversal/loops). It supplies the *tool* to walk a recursive
structure safely — `StructuralRecursion` with `decreases node.children` — but it does not, by itself, decide
whether the recursive *type* may be declared. That is the open axis.

## 3. Canon evidence around recursive `TypeDecl` — SILENCE (Q1 second half, Q2)

- **`OOF-F1` is scoped to `def` / computation only** — "Recursive **def** (self-reference)"
  (`ch2:343`). It says nothing about `type`.
- **TypeDecl (§2.5, PROP-015):** *"User-defined structural record types… Structural (not nominal)… Optional
  fields (`?`) map to `Option[T]`"* (`ch2:303-318`). **No mention of self-reference** — neither permitted nor
  forbidden.
- A repo-wide canon grep finds **no** recursive-type / self-referential-type / cyclic-type rule anywhere in
  `docs/spec` or `source/`.

**Q2 answer:** `OOF-F1` is computation-only. **Canon does not currently govern recursive `TypeDecl` — it is
silent.**

---

## 4. Lab behavior probe (Q4) — recursive *type* is ALLOWED; recursive *traversal* is CLOSED

Three temp fixtures (`/tmp`, uncommitted) compiled with the live lab compiler
(`igniter_compiler compile <src> --out …`, `lang/igniter-compiler`):

| Probe | Fixture | Result (`stages` / `status`) |
| --- | --- | --- |
| **declare + read field** | `type Node { label:String  children:Collection[Node] }` + `pure contract ReadRoot { input root:Node  compute kids:Collection[Node] = root.children }` | **`status: ok`** — parse ok, **typecheck ok**, 0 diagnostics |
| **construct nested literal** | `compute t:Node = { label:"a", children:[ { label:"b", children:[] } ] }` | **`status: ok`** — recursive *construction* typechecks (`tc_infer` depth 4) |
| **self-recursive traversal** | `compute … = map(root.children, c -> call_contract("WalkTree", c))` (self-call) | **`status: oof`** — `OOF-TY0`: *"self-recursion via 'WalkTree' is closed in v0; use `recur()`"* |

**So the lab today:**
- **Accepts** a recursive `TypeDecl` (it neither rejects nor loops). `build_type_shapes`
  (`typechecker.rs:630-643`) stores **shallow** field type-IRs (`type_ir` does not expand the referenced
  type), so `Node.children : Collection[Node]` is a finite registered shape, not an infinite expansion.
- **Constructs** recursive values fine (nested record-literal inference upgrades each level to `Node`).
- **Closes** recursive *traversal* by self-call (`OOF-TY0`, consistent with the Covenant law), pushing you to
  managed `recur()` (Ch13, partially gated: `stdlib_calls.rs:2353` "gate 5 — return Unknown").
- Is **bounded-safe even on the silent-allow path:** a `typechecker.infer_expr.max_depth` budget
  (limit **1000, mode `fatal`**, env-overridable; `lab_only_p2` instrumentation in every report) caps runaway
  recursive *inference/construction*, so a deeply/maliciously nested literal fails the budget rather than
  hanging. The acceptance is *unspecified-but-bounded*, not a trap.

**Net (Q4):** recursive record types **parse + typecheck + construct**; they do **not** loop or mis-model.
Only arbitrary-depth `.ig` traversal is refused — which is the computation axis, already canon-correct.

---

## 5. What ViewArtifact / HTML actually needs (Q5) — and the impact

A view tree is **finite by construction** (built by `map` over finite rows) and **traversed by the host
projector** (Rust, depth-bounded), not by `.ig`. So the view engine needs exactly what the lab already
permits: **declare + finitely construct a recursive descriptor; let the host walk it.** It does *not* need
`.ig`-side recursive traversal (the closed axis).

| Option for ViewArtifact | Fit |
| --- | --- |
| recursive `HtmlNode.children` authored in `.ig` | **works today** (probe §4) for finite/bounded depth; arbitrary data-driven depth would need `recur()` (Ch13, deferred) |
| bounded non-recursive layout records (P26 `list`/`item`) | safe, current incremental path; no recursion needed |
| host-owned tree traversal over JSON | **already the model** — descriptor crosses as JSON, `render_html` walks `serde_json::Value` (`frame-ui/igniter-render-html`), naturally depth-bounded |
| flat descriptor + helper conventions | current v0 (link node, helpers) |

**Impact on the view-engine direction:** the earlier worry that "recursion is the hard collision" is
**softened by evidence** — recursive *types* are already expressible and constructible; the *engine* (a
recursive semantic IR + projector pipeline, the deferred `LAB-IGNITER-WEB-VIEW-ENGINE-MODEL-READINESS`) is
the real missing piece, **not** the type system. The flat-ViewArtifact incremental path can continue
unchanged; a future recursive descriptor is not blocked by the language.

---

## 6. Which best preserves Igniter's law (Q6) + recommendation (A/B/C/D)

Law to preserve: *"declared, bounded, auditable repetition."*

| Option | Verdict |
| --- | --- |
| **A. Forbid recursive `TypeDecl`** | **Reject.** Over-restrictive: it would *break* already-working recursive descriptors and the natural view-tree path, for a hazard that is finite-by-construction and already depth-budgeted. |
| **B. Allow recursive `TypeDecl` only with managed structural traversal** | **Recommended canon direction.** A recursive shape may exist; any *walk* must be managed structural recursion (`recur()`/`decreases node.children`) or a bounded host walker. Extends Ch13's law to data shape — "declared, bounded, auditable" holds for both axes. |
| **C. Allow host-owned recursive descriptors; keep `.ig` traversal closed** | **Recommended v0 posture (already de-facto).** `.ig` declares + finitely constructs; host projectors traverse JSON with depth bounds; `.ig` self-traversal stays `OOF-TY0`. Zero lab change; exact ViewArtifact/HTML fit. |
| **D. Defer** | **Reject.** The question recurs; we now have empirical clarity, so capture it. |

**Recommendation: C now, B as the canon ask.** C is *already true and bounded* — document it and keep
shipping. B is the principled ratification that replaces canon's silence and unifies the two axes under one
law. (C is a strict subset of B: C = "host walks it"; B adds "or `.ig` walks it via managed `recur()`.")

---

## 7. Exact wording for the canon-facing question (proposed PROP snippet)

> **Canon question — recursive `TypeDecl` policy (proposed PROP-0xx / Ch2 §2.5 + Ch13 addendum).**
> `OOF-F1` closes self-referential `def` (computation). Canon is currently *silent* on self-referential
> `type` (data shape), and the reference Rust compiler accepts it (registers a shallow shape; refuses
> `.ig`-side self-traversal via `OOF-TY0`; bounds inference depth at 1000/fatal).
>
> **Decide:** does a self-referential structural `TypeDecl` (e.g. `type Node { children : Collection[Node] }`)
> get (A) an explicit refusal rule, (B) an *allow-with-managed-traversal* rule — the shape is permitted, but
> every traversal must be managed structural recursion (`recur()` + `decreases <variant>.tail/.rest`, Ch13) or
> a host walker with a declared depth bound — or (C) allow-with-host-traversal-only (B minus the `.ig`
> `recur()` traversal)?
>
> **Lab recommendation: B**, with **C** as the v0 conformance subset already satisfied. If B, specify: the
> depth-bound obligation for host walkers, and whether `recur()` over a `decreases node.children` dotted-path
> variant lifts the v0 `OOF-R3` dotted-path refusal for *structural* (non-fuel) recursion.

---

## Verification

```bash
# canon (actual location; card's /Users/alex/dev/projects/igniter has no spec)
cd /Users/alex/dev/projects/igniter-workspace/igniter-lang
rg -n "recursion|recursive|recur|decreases|OOF-F1|TypeDecl|children : Collection" docs source

# lab
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
rg -n "recursive|recur|decreases|OOF-F1|OOF-TY0|TypeDecl|children : Collection|HtmlNode|ViewArtifact" \
  lang/igniter-compiler server/igniter-web frame-ui/igniter-render-html lab-docs/lang .agents/work/cards/lang

# probe (temp, uncommitted): igniter_compiler compile /tmp/rec_{decl,make,walk}.ig --out …
#   rec_decl → status ok · rec_make → status ok · rec_walk → status oof (OOF-TY0 self-recursion closed)

git diff --check   # clean (probes live in /tmp; no repo source changed)
```

---

## Reporting

- **Canon/lab answer (one paragraph):** Canon firmly settles **computation** recursion — no free recursion,
  managed repetition only (Covenant law; Ch13 `recur()`/`decreases`; `def` `OOF-F1`) — and the lab enforces it
  (`OOF-TY0` self-recursion closed). Canon is **silent** on **data-shape** recursion (recursive `TypeDecl`);
  `OOF-F1` is computation-only and §2.5 says nothing. The lab **already accepts** recursive record types: they
  parse, typecheck, and construct (`status: ok`), bounded by a 1000/fatal inference-depth budget; only
  arbitrary-depth `.ig` traversal is refused. So recursive *shapes* are usable today; recursive *walks* are
  the closed (computation) axis.
- **Chosen recommendation:** **C now → B as the canon ask** (allow recursive `TypeDecl`, traversal managed or
  host-bounded). Not A (breaks working/needed shapes), not D (question recurs).
- **Flat ViewArtifact work:** **continue unchanged.** The incremental path (link node done, bounded
  `list`/`item` next) is unaffected; a future recursive descriptor is *not* blocked by the language, so no
  rework is forced.
- **Next canon-facing action:** route the §7 wording to canon as a PROP question (Ch2 §2.5 + Ch13 addendum) —
  ratify B and specify the host-walker depth-bound + the `decreases node.children` structural lift. Lab stays
  evidence-only until canon rules.
