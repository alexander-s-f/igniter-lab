# Card: LAB-STDLIB-REGEXP-P1 — regexp stdlib pressure/readiness before lang adoption

**Lane:** standard / lab-pressure-readiness
**Skill:** idd-agent-protocol
**Status:** OPEN
**Date opened:** 2026-06-18
**Delegation label:** OPUS-STDLIB-REGEXP-A
**Authority:** Lab evidence/design only. Not canon `LANG-*` yet. No runtime dependency or compiler change.

## Why this card exists

IgWeb routing pressure exposed a deeper stdlib gap: expressive path and text pattern
matching should not be solved by a Rust route table in `igniter-server`, nor by ugly
manual `split/count/last` contracts.

Before opening a canon-ish `LANG-STDLIB-REGEXP-*` implementation, we need a lab
readiness packet that decides what `stdlib.regexp` should mean in Igniter:

- which operations belong in v0;
- what return shapes fit current `Option`/`Collection`/`Map` reality;
- how invalid patterns fail;
- how host/Rust delegation works;
- how this supports route patterns without making regexp the final authoring DX.

The center of gravity is not "add regex because web routing wants it". The center is:

> A deterministic, host-delegated text pattern capability in stdlib, narrow enough
> to be safe and testable, rich enough to unblock route params and common validation.

## Read first (verify-first, live code wins)

- `lab-docs/lang/lab-igniter-web-routing-pure-ig-p1-v0.md`
- `lab-docs/lang/lab-igniter-web-routing-dx-shape-p2-v0.md` if present
- `.agents/work/cards/lang/LAB-IGNITER-WEB-ROUTING-DX-SHAPE-P2.md`
- `igniter-apps/web_router/PRESSURE_REGISTRY.md`
- `igniter-apps/web_router/serve.ig`
- `igniter-apps/web_router/types.ig`
- `lab-docs/lang/lab-string-value-semantics-bounds-and-unicode-proof-v0.md`
- `lab-docs/lang/lab-text-unicode-semantics-authority-and-runtime-policy-design-v0.md`
- `lab-docs/lang/lab-text-unicode-runtime-ops-implementation-proof-v0.md`
- `igniter-stdlib/stdlib/core/string.ig`
- `igniter-stdlib/stdlib/collections.ig`
- `igniter-compiler/src/typechecker.rs`
- `igniter-vm/src/vm.rs`
- current dependency manifests (`rg -n "regex|fancy-regex|pcre|onig" Cargo.toml **/Cargo.toml`)

## Goal

Produce a readiness packet answering:

> What exact `stdlib.regexp` v0 should Igniter expose, and what implementation
> route should later prove it, without creating unsafe regex semantics, ugly APIs,
> or false canon?

This card may recommend implementation later, but must not implement it.

## Required deliverable

Write:

`lab-docs/lang/lab-stdlib-regexp-p1-v0.md`

Then close this card with a compact report.

## Required research questions

1. **Current policy baseline.**
   Existing string docs say pattern operations are literal and regex is deferred.
   Summarize the current policy and why opening regexp now is justified by new
   pressure rather than random feature growth.

2. **Host delegation model.**
   Should `stdlib.regexp` delegate to Rust's `regex` crate, another crate, or a
   host-provided adapter? Compare at least:
   - Rust `regex` crate (linear-time, no lookaround/backrefs);
   - richer engines (`fancy-regex`, PCRE/onig-like) as rejected/deferred options;
   - a trait/host adapter seam for future richer implementations.

3. **Safety policy.**
   Decide v0 guarantees:
   - deterministic / no catastrophic backtracking;
   - no filesystem/network/locale/global state;
   - pattern length / haystack length budget if needed;
   - invalid pattern behavior;
   - Unicode mode policy;
   - no replacement/mutation in v0 unless explicitly justified.

4. **Function surface.**
   Propose the smallest v0 API. Evaluate at least:
   ```igniter
   def matches(text: String, pattern: String) -> Bool
   def capture(text: String, pattern: String, index: Integer) -> Option[String]
   def captures(text: String, pattern: String) -> Collection[String]
   def capture_named(text: String, pattern: String, name: String) -> Option[String]
   def split_regex(text: String, pattern: String) -> Collection[String]
   ```
   You may reject some. Explain why.

5. **Return-shape fit.**
   Current `Map` construction and `Option` ergonomics are imperfect. Which return
   shapes are useful now and which should wait? Avoid an API that looks elegant on
   paper but is painful in `.ig` today.

6. **Error taxonomy.**
   How should invalid regex patterns fail?
   Options: compile-time OOF when literal; runtime operational error; `Result`-like
   variant; `Option` none. Pick a lab v0 policy and explain how diagnostics should
   look later.

7. **Literal pattern vs dynamic pattern.**
   Should v0 require literal pattern strings for typechecking/diagnostics, or allow
   dynamic patterns? If both, what is the safety and diagnostic split?

8. **Route pressure tests.**
   Show how regexp would help IgWeb without becoming final routing authoring syntax:
   - `/todos/([0-9]+)$` -> id;
   - `/todos/([0-9]+)/done$` -> id;
   - `/accounts/([0-9]+)/todos/([0-9]+)$` -> account_id + todo_id;
   - `/webhooks/([a-z0-9_-]+)$` -> vendor.

9. **Validation/extraction pressure tests.**
   Include at least email-ish validation, UUID/id validation, phone-ish validation,
   and extracting a prefix/suffix from a string. Keep them practical, not regex golf.

10. **Relationship to WR-P04.**
    Does regexp replace `split`/`nth`/Option improvements, or merely unblock routing
    while those remain desirable? Be precise. Do not let regexp hide core collection
    ergonomics problems.

11. **Relationship to IgWeb route DSL.**
    Explain how future beautiful syntax:
    ```text
    route POST "/todos/:id/done" -> TodoDone(id)
    ```
    could lower to regex internally, while app authors do not usually write regex.

12. **Implementation path.**
    Recommend the next card order. For example:
    - P2 proof-local Rust host/stdlib adapter over `regex`, no compiler semantics;
    - P3 compiler/typechecker registration + VM dispatch if P2 proves shape;
    - P4 IgWeb lowering uses regexp as substrate.
    Or reject this order and propose a better one.

## Suggested v0 stance (not authority)

A conservative candidate:

```igniter
module stdlib.regexp

def matches(text: String, pattern: String) -> Bool

def capture(text: String, pattern: String, index: Integer) -> Option[String]

def captures(text: String, pattern: String) -> Collection[String]
```

Policy:
- delegate to Rust `regex` crate (linear-time, Unicode by default);
- no lookaround/backrefs in v0;
- literal invalid pattern should eventually become structured diagnostic;
- dynamic invalid pattern is runtime operational error;
- named capture waits until `Map`/record ergonomics are better, unless the packet
  proves `capture_named` is still worthwhile;
- replacement/split-by-regex waits.

This suggested stance is deliberately conservative. Verify or replace it.

## Required pressure fixture snippets

The packet must include small `.ig`-style snippets for:

### Route id extraction

```igniter
compute is_done_route = matches(req.path, "^/todos/([0-9]+)/done$")
compute todo_id = capture(req.path, "^/todos/([0-9]+)/done$", 1)
```

### Nested route extraction

```igniter
compute account_id = capture(req.path, "^/accounts/([0-9]+)/todos/([0-9]+)$", 1)
compute todo_id = capture(req.path, "^/accounts/([0-9]+)/todos/([0-9]+)$", 2)
```

### Webhook vendor extraction

```igniter
compute vendor = capture(req.path, "^/webhooks/([a-z0-9_-]+)$", 1)
```

If these snippets are awkward because `Option[String]` is awkward, say so and route
that pressure to the right language gap.

## Acceptance

- [ ] Packet answers all 12 research questions.
- [ ] Existing literal string/no-regex policy is summarized accurately.
- [ ] Host/Rust delegation model is explicit.
- [ ] Safety policy rejects catastrophic/backtracking-prone behavior unless gated.
- [ ] v0 API is small and justified.
- [ ] Invalid-pattern behavior is specified for literal and dynamic patterns.
- [ ] Route, nested route, webhook, and validation pressure fixtures are included.
- [ ] Relationship to WR-P04 and IgWeb route DSL is explicit.
- [ ] Next implementation cards are ordered.
- [ ] No compiler/parser/vm/stdlib implementation in this card.
- [ ] No dependency change in this card.
- [ ] No canon `LANG-*` claim.

## Closed surfaces

- No code changes except an optional tiny pointer if truly necessary.
- No new dependency.
- No compiler/parser/typechecker/VM edits.
- No production/live behavior.
- No regex-based router in `igniter-server`.
- No public listener, DB, SparkCRM, or vendor work.
- No canonical stdlib claim yet.
- No rich regex engine with backtracking unless explicitly deferred/gated.

## Desired conclusion shape

The closeout should make a clean call:

```text
LAB-STDLIB-REGEXP-P1 result:
  recommended v0 API = ...
  delegated engine = ...
  safety policy = ...
  next card = ...
  canon promotion = NOT YET / gated by proof
```

If the research finds regexp is the wrong first move, say that plainly and propose
the better primitive. The goal is gravity, not feature accumulation.
