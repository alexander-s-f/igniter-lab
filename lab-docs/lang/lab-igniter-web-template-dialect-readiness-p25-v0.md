# lab-igniter-web-template-dialect-readiness-p25-v0

Card: `LAB-IGNITER-WEB-TEMPLATE-DIALECT-READINESS-P25`
Route: standard / dialect readiness · Skill: idd-agent-protocol
Status: research-only readiness packet (no code, no parser, no new extension; no canon claim)
Date: 2026-06-25
Builds on: P24 HTML expression model (keystone) · Data Projection P1-P5.

> **Authority boundary.** Research only. No parser, no template engine, no `.ig.html` implementation, no
> dependency on any template library. Every concrete claim cited against live source.
>
> **Meta-Architect stop condition (honored):** a template dialect is acceptable *only* as a projection
> dialect that lowers cleanly to the `ViewArtifact` descriptor or pure `.ig`. **If a proposed `.ig.html`
> feature cannot lower to the descriptor, that is a fork, not a feature — stop and surface it; do not drag a
> new runtime/language through by inertia.** This packet's central finding is exactly where that fork lies.

---

## Headline

**Recommendation: HOLD `.ig.html`.** The projection-dialect slot is **already filled** by `.igv` — a live
declarative screen DSL that lowers deterministically to `ViewArtifact` JSON with no runtime
(`frame-ui/igniter-ui-kit/src/igv.rs:15-30`). A second dialect (`.ig.html`) would add **HTML-shaped authoring
ergonomics, not capability**. Its expressiveness ceiling is the `ViewArtifact` vocabulary (P26), so building
it *ahead* of that vocabulary is premature — and any attempt to make `.ig.html` express *more* than the
descriptor is the fork the Meta-Architect named: it would smuggle a runtime, not lower to data.

**If ever pursued**, `.ig.html` must lower exactly like `.igweb` and `.igv`: to a pure `.ig` contract
producing a `ViewArtifact` (deterministic, byte-identical, no hidden engine). Inputs declared by contract
signature; loops/conditionals lower to `.ig` HOFs; escaping stays projector-owned; no raw HTML by default.

---

## 1. External inspiration (short, not a review)

| System | Idea worth borrowing | What to reject |
| --- | --- | --- |
| Phoenix **HEEx** | compile-time templates, **default-escaped**, typed `assigns`, no string concat | the `~H` macro is HTML-string-shaped output; we target a *descriptor*, not HTML strings |
| Elixir **Temple** | **HTML-as-data** (markup expressed as data structures, compile-time) | — (closest match: it confirms "HTML as data" is viable and Igniter-native) |
| **Slim / Haml** | terse, indentation-driven structure | they target HTML *strings*; we target the ViewArtifact descriptor |
| **Svelte / Astro** | component compilation | a **client runtime / hydration** — out of an SSR-descriptor model entirely |

**Distilled stance:** borrow *compile-time lowering + default escaping + typed inputs* (HEEx/Temple); reject
*string-targeting* (Slim/Haml) and *client runtime/hydration* (Svelte/Astro). The Igniter-native result is
**HTML-as-data that lowers to the descriptor** — never markup strings, never a runtime.

---

## 2. The reframe: `.igv` already occupies the dialect slot

`.igv` is not a sketch — it is live and is *already a projection dialect over `ViewArtifact`*:

```text
view <screen> <layout> {                                  -- igv.rs:15-30 (grammar)
  source <name> = <Contract>      // → sources.<name> {contract, mode:"read"}
  field  <id> <kind> "<label>" [opts] required   // → regions.main.fields[]
  action <name> = <Contract> { input … validate … effect … }   // → actions.<name>
  submit <action>
}
```

It *"LOWERS to the proven ViewArtifact JSON… SUGAR over the artifact, nothing more… deterministic… does not
touch `.ig`"* (`igv.rs:1-12`). The canonical schema states the ordering principle explicitly: the artifact is
**data**, *"the reason it comes before a text DSL (`.igv`)"* (`frame-ui/igniter-ui-kit/src/view_artifact.rs:6-7`).

So the dialect question is **not** "does Igniter need a declarative view dialect" (it has one). It is: **does
an HTML-*shaped* dialect (`.ig.html`) earn its place beside `.igv` + ViewArtifact records + helper contracts?**

---

## 3. If `.ig.html` existed — the answers (Q1-Q7), all bias-compliant

1. **Lowering target (Q1):** a **pure `.ig` contract returning `ViewArtifact`** (equivalently, lowering to
   the same `RenderView { view : ViewArtifact }` path). The `.igweb`→`.ig` and `.igv`→ViewArtifact-JSON
   precedents are the discipline (`lang/igniter-compiler/src/igweb.rs`; `igv.rs:115`). **Not** a host template
   AST, **not** a direct HTML string, **not** a runtime.
2. **Data inputs (Q2):** by **contract/function signature** — typed inputs (e.g. `input rows :
   Collection[TodoRow]`, the projected collection). **No untyped implicit locals** (design bias). This is how
   `.igweb` handlers and `.igv` `source` bindings already declare data.
3. **Loops/conditionals (Q3):** lower to **`.ig` HOFs / comprehension** — `{for r in rows}` → `map(rows, …)`
   / `[ … for r in rows ]`; `{if c}` → `if`/`filter`. No template control-flow runtime; the lowered `.ig` is
   the inspectable truth (same as comprehension → map/filter, byte-identical).
4. **Escaping/XSS (Q4):** **default-escaped text; no raw-HTML opt-in in v0.** Escaping stays wholly
   **projector-owned** (`igniter_render_html` escapes every leaf; structured input → "no markup-injection
   surface", `frame-ui/igniter-render-html/src/lib.rs:9-13,58`). The dialect changes *authoring*, never the
   safety boundary. A typed `Html` vs `String` distinction + raw opt-in would be a *later* descriptor concern
   (P26), not a dialect feature.
5. **Composes with Data Projection (Q5):** the dialect's typed input *is* the projected `Collection[<AppRow>]`
   from P6. `.ig.html` would author the transform-to-view step (P4) in HTML shape, lowering to the same
   `map → HtmlNode → ViewArtifact` it does today.
6. **Why worth adding vs helpers/records (Q6):** the *only* marginal value over `.igv` + records + helpers is
   **familiar HTML-shaped ergonomics** for authors who think in markup. That is a DX nicety, **not a
   capability** — `.igv` already expresses sources/fields/actions/submit declaratively. Worth adding *only* if
   evidence shows app authors are materially slowed by records/`.igv` for HTML views **and** the ViewArtifact
   vocab (P26) is settled enough to be a stable lowering target.
7. **Smallest proof if ever (Q7):** a `.ig.html` fragment with one interpolation, one `for`, one `if`,
   lowering **byte-identically** to the equivalent hand-authored `RenderView`/ViewArtifact output — the same
   byte-identity discipline that gates `.igweb` (`igweb_lowering_tests`), comprehension
   (`collection_comprehension_tests:5`), and `.igv`. No runtime, no new value kind.

---

## 4. The fork (the Meta-Architect's stop condition, located precisely)

`.ig.html` is a clean projection dialect **iff its expressiveness ⊆ what `ViewArtifact` + `.ig` can hold.**
The fork is reached the moment a desired `.ig.html` feature *cannot* lower to the descriptor:

| Desired feature | Lowers to descriptor? | Verdict |
| --- | --- | --- |
| interpolation `{ r.title }` | yes — a leaf field from a record | dialect-OK |
| `{for r in rows}` / `{if c}` | yes — `map`/`filter`/`if` in `.ig` | dialect-OK |
| flat form/list (label/button/input) | yes — current vocab | dialect-OK |
| **arbitrary nesting / sections / repeated sub-trees** | **no** — `ViewArtifact` is flat/non-recursive (`igweb.rs:36`) | **FORK → P26** (evolve the descriptor), not a dialect runtime |
| **partials/includes with own scope, slots** | **no** — needs a component/scope model | **FORK → P26 / runtime**; reject as dialect |
| **stateful components / client interactivity / hydration** | **no** — needs a client runtime | **REJECT** (out of SSR-descriptor model) |

**Rule:** if `.ig.html` is wanted *to escape the descriptor's limits*, that is not a dialect — it is either a
ViewArtifact vocabulary evolution (**P26's job**) or a hidden runtime (**rejected**). The dialect's ceiling is
the descriptor's ceiling. This is why P25 **holds** and points at **P26**: *evolve the data model first; a
dialect is sugar over whatever the descriptor can already express.*

---

## 5. Why defer (and what would change the decision)

**Defer because:**
1. `.igv` already fills the declarative-view-dialect slot (§2).
2. v0 TodoApp HTML ships on records + helpers (P24 Idiom A) — no dialect needed.
3. A dialect's lowering target (ViewArtifact vocab) is *itself* under evolution (P26); building sugar over a
   moving target is premature.
4. The value is ergonomics, not capability — defer until measured author pain + a settled vocab.

**What would justify revisiting:** (a) P26 settles a richer-but-bounded vocab, *and* (b) authoring real
TodoApp views in records/`.igv` proves materially worse than HTML-shaped syntax would be, *and* (c) the
lowering stays pure (descriptor/`.ig`, byte-identical). All three — not any one — flip the decision.

---

## 6. Smallest future proof card (if/when revisited)

`LAB-IGNITER-WEB-IGHTML-DIALECT-LOWERING-PROOF` (HOLD until P26 + author-pain evidence): a non-parser proof
that a fixed `.ig.html` fragment (1 interpolation + 1 `for` + 1 `if`) lowers byte-identically to a
hand-authored `RenderView` ViewArtifact over a `Collection[TodoRow]` — reusing the `.igweb`/`.igv`
byte-identity harness. No engine, no runtime; if the fragment cannot lower, the card returns the §4 fork
instead of an implementation.

---

## Verification

```bash
rg -n "Projection Dialect|\.igv|\.ig.html|template|Temple|ViewArtifact|HtmlNode|escape|raw" \
  lab-docs .agents server lang frame-ui \
  > /tmp/igniter-template-dialect-grep.txt        # 4608 hits

git diff --check                                   # clean
```

---

## Reporting

- **Recommended stance on `.ig.html`:** **HOLD / defer.** The projection-dialect slot is already filled by
  `.igv`; a second, HTML-shaped dialect adds ergonomics, not capability, and its ceiling is the ViewArtifact
  vocab (P26). Do not make it the next implementation.
- **Lowering target:** if ever built, a **pure `.ig` contract returning `ViewArtifact`** (the `.igweb`/`.igv`
  discipline) — byte-identical, deterministic, **no hidden runtime, no HTML strings, no untyped locals**.
- **Safety model:** default-escaped, projector-owned escaping (unchanged from P24); **no raw HTML by
  default**; typed leaves only.
- **Next / hold decision:** **HOLD.** Route to **P26** (evolve the descriptor vocab first). The fork to watch:
  any `.ig.html` feature that cannot lower to the descriptor is a runtime-in-disguise — stop and surface it.
