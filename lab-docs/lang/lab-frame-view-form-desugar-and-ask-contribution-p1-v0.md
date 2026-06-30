# LAB-FRAME-VIEW-FORM-DESUGAR + ASK1/ASK2 canon contribution (P1)

Status: lab precedent DONE (e2e green) + a grounded contribution for the canon owners of
`LANG-FORM-VOCABULARY` / `LANG-TYPED-CONTRACT-REF`. No canon compiler changed.
Lane: igniter-lab / frame-ui → igniter-lang (canon) / DX
Date: 2026-06-27
Reads with: `lab-frame-view-language-pressure-p1-v0.md`, the dx-view-D specimens, the P2–P4 runtime
bridge packets.

## The reframe (verify-first on the canon compiler — important)

A read of the live canon compiler changed both asks:

- **ASK1 "cross-module `call_contract`" cuts AGAINST canon intent.** `LANG-TYPED-CONTRACT-REF-P5`
  (CLOSED, 71/71) built and proved cross-module resolution — but for the typed `uses ContractName`
  ref, NOT for `call_contract`. The proposal states plainly that it *"does NOT make `call_contract`
  cross-module (a separate future decision)"* and keeps `call_contract` a same-module *stringly-typed
  pressure source*. So extending `call_contract` across modules would fight the language's chosen
  design. Concretely it is feasible — S-scope (~40–60 lines in `typechecker.rb::infer_call_contract`,
  reusing the P5 `resolve_import_scope_for` path) — but it front-runs an owned decision; **we do not
  pursue it.**
- **ASK2 (forms) is the right unlock, and it SUBSUMES ASK1.** A form `col { row { … } }` lowers to a
  nested `InvocationIntent` over typed `uses` refs — and `uses` cross-module is already proven (P5). So
  forms give BOTH the nesting ergonomics AND a reusable cross-module `elements.ig`, the canon way. But
  `LANG-FORM-VOCABULARY` is an OWNED track (P1 design 61/61, P2 planning "READY FOR NARROW P3"); P3/P4
  are unimplemented and awaiting the owners' authorization. We therefore contribute, not implement, in
  canon.

## What we built — a lab precedent (no canon change)

`igniter-frame/src/igv_desugar.rs` — a SOURCE-TO-SOURCE desugarer that expands the terse invocation
form into the exact `call_contract`-based `.ig` we already compile/run/render. It is not a `.igv`
runtime and not "Rust that returns a string": its output is `.ig` source that flows through the proven
pipeline.

Authored source — `web/list_view.form` (11 lines):

```text
col pad=16 gap=12 {
  row flex=1 gap=12 {
    col fixed=248 pad=12 gap=8 {
      leaf "Review Ada's lead" select fixed=40
      leaf "Call Grace back" select fixed=40
      leaf "Send Linus the quote" select fixed=40
      button "+ add item" add fixed=40
    }
    col flex=1 pad=18 gap=14 {
      leaf "Review Ada's lead" select fixed=30
      button "mark done" toggle fixed=48
    }
  }
}
```

### End-to-end proof (real toolchain)

```bash
cd frame-ui/igniter-frame
cargo run --no-default-features --example desugar -- web/list_view.form > /tmp/generated_view.ig   # 71-line .ig
ruby -I …/igniter-lang/lib …/igniter-lang/bin/igc compile /tmp/generated_view.ig --out /tmp/generated_view.igapp   # ok
cargo run --manifest-path lang/igniter-vm/Cargo.toml -- run --contract /tmp/generated_view.igapp \
  --entry View --inputs /tmp/empty-input.json --json   # status: success
```

Result: `status: success`, Element tree with all labels (`Review Ada's lead`, `Call Grace back`,
`Send Linus the quote`, `+ add item`, `mark done`) and intents `[add, select, toggle]`. The captured
runtime output (`tests/fixtures/list_view_form.runtime.json`, command-produced) renders through
`render_ig_view` — test `desugared_form_view_renders_through_the_bridge`. **74 frame-ui tests / 0
fail** (4 desugar unit + 1 form render added). `git diff --check` clean.

So: **terse form → desugar → `.ig` → igc → igniter-vm → Element → frame-ui render**, all green, proving
the ASK2 ergonomics and the EXACT lowering, with zero canon change.

## Contribution to the canon owners (LANG-FORM-VOCABULARY P3/P4)

The recon (paths verified) found the precise gaps and the one real hazard; here is the contribution:

1. **The parse-ambiguity is real but resolvable.** A `Tag { … }` form body whose children are *bare
   expressions* collides with the record-literal parser, which on `{` expects `<ident> ":"`
   (`parser.rb::parse_record_or_block`, ~:2013). RESOLUTION the precedent validates: **the form body is
   a sequence of NODES, each beginning with a TRIGGER WORD** (`col`/`row`/`leaf`/`button` here), and
   attributes are `key=value` (not `key: value`). A `Tag { word … }` (no colon after the first inner
   token) is unambiguously a form body, distinguishable from a record `{ ident : … }` with one token of
   lookahead — exactly how the desugarer's parser disambiguates. This sidesteps the record collision
   without backtracking.
2. **Minimal P4 invocation slice** (matches the P2 plan): parser emits a `form_invocation` AST node
   (`trigger`, `attrs`, `children`); a post-classify / pre-typecheck form-resolution pass rewrites it to
   the existing `call` node shape — `call_contract`-equivalent over the typed `uses` ref — with a
   resugaring trace. No typechecker change (forms are already lowered to `call`). The desugarer's output
   is a **concrete reference for that `call` shape**: `call_contract("Col", attrs_i, [node_a, node_b])`,
   leaves `call_contract("Leaf", attrs_i, "text", "intent")`, post-order so children precede parents.
3. **ASK1 disposition:** do not extend `call_contract` cross-module. The desugarer INLINES the element
   library today (because cross-module `call_contract` is unavailable by design); once forms lower to
   `uses` refs, the same library is referenced across modules the canon way (P5-proven), and the inline
   preamble drops out. No language-isolation risk is taken.
4. **Optional/default fields stay HELD** (totality/determinism trap) — unchanged.

## Files (this slice)

- `frame-ui/igniter-frame/src/igv_desugar.rs` (+ `lib.rs` wiring) — the desugarer + 4 unit tests.
- `frame-ui/igniter-frame/examples/desugar.rs` — `.form` → `.ig` emitter.
- `frame-ui/igniter-frame/web/list_view.form` — the authored terse source.
- `frame-ui/igniter-frame/tests/fixtures/list_view_form.runtime.json` — command-produced runtime output.
- `frame-ui/igniter-frame/tests/ig_runtime_bridge_tests.rs` — `desugared_form_view_renders_through_the_bridge`.

## What remains (for the canon owners, with UI evidence behind it)

- LANG-FORM-VOCABULARY P3 (vocabulary metadata) → P4 (invocation lowering) — the desugarer is the
  working reference for P4's lowering target and the body-grammar disambiguation.
- LANG-TYPED-CONTRACT-REF stays the cross-module substrate forms lower onto (no new work).
