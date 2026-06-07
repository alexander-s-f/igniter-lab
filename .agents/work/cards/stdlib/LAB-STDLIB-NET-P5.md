# LAB-STDLIB-NET-P5

**Card ID:** LAB-STDLIB-NET-P5
**Category:** stdlib / io / network
**Track:** lab-experimental-io-network-hardening-proof-v0
**Route:** EXPERIMENTAL / LAB-ONLY / PROOF
**Analog to:** LAB-STDLIB-IO-P9
**Date:** 2026-06-07
**Status:** DONE

---

## D — Deliverables

- `igniter-view-engine/fixtures/network_capability_hardening/` (8 JSON fixtures)
- `igniter-view-engine/proofs/network_hardening_proof.rb` (proof runner)
- `lab-docs/stdlib/lab-experimental-io-network-hardening-proof-v0.md`
- `.agents/work/cards/stdlib/LAB-STDLIB-NET-P5.md` (this receipt)

---

## S — Summary

All 5 open questions deferred from P1–P4 were resolved and proved through 44 explicit
checks. The proof resolves every tension item from LAB-STDLIB-NET-P1 §T.

**Resolutions:**

| Open question | Resolution | Key check |
|---|---|---|
| Glob host matching semantics | Opaque-literal: `*.example.com` ≠ `api.example.com`; glob expansion deferred to runtime | NET-GLOB-2,8 |
| `direction:"both"` compose | AND semantics: `compose(connect_only, listen_only)` = both bits false | NET-BOTH-2 |
| 3-hop delegation chains | Transitivity proved: G1→G2→G3 valid implies G1→G3 valid; compose is associative | NET-CHAIN-3,9 |
| Bind-address Condition 8 | Fires only when both parent and child have non-null bind addresses that differ | NET-BIND-3,4,5 |
| Wildcard `*` + `loopback_only` | Independent policy checks: `*` cannot override `loopback_only:true` | NET-WILD-3,4 |

**All 7 E-NET-DELEGATION-* codes** proved producible in a single maximally violating
delegation (NET-STABLE-2).

**Closed-surface maintained:** No real sockets. No igniter-lang modifications. P5 does
not depend on P3 FFI stub. Guard scan uses split-string technique to avoid self-triggering.

---

## Proof Chain (complete)

| Card | Checks | Scope |
|---|---|---|
| LAB-STDLIB-NET-P2 | 53/53 | Schema, delegation algebra, safety policies NET-1–NET-6 |
| LAB-STDLIB-NET-P3 | 61/61 | FFI surface contract, stub mode, operation sequence |
| LAB-STDLIB-NET-P4 | 42/42 | Compiler escape classification, all 10 E-NET-* codes |
| LAB-STDLIB-NET-P5 | 44/44 | Hardening: glob, direction:both, chains, bind-address, wildcard+loopback |
| **Total** | **200/200** | |

---

## T — Tensions / Remaining Open

**1. Compose does not preserve bind_address.**
The compose operator sets `bind_address: nil` in the result, discarding both parents'
bind addresses. Whether the composed grant should inherit one parent's bind address
(and which) is undefined. Deferred to P6.

**2. Dead grant detection.**
`compose(connect_only, listen_only)` produces a grant where no operation is permitted.
Validated as algebraically correct (AND semantics), but such grants are operationally
useless. A future card could add dead-grant detection at `validate_schema` time.

**3. Multi-level wildcard.**
`*` is the only wildcard sentinel. No `**` recursive or single-char `?` patterns.
If runtime glob expansion is added, its semantics need a dedicated proof.

---

## R — Recommended Next

Three independent paths, each valid:

**LAB-STDLIB-NET-P6** — Dead grant + compose bind_address gap (technical debt from §T)

**LAB-LANG-HTTP-TYPES-P1** — Prove `ContractRef[HttpRequest, HttpResponse]` middleware
dispatch (unproven claim from LAB-RACK-P1; highest leverage for web framework direction)

**LAB-WEB-FRAMEWORK-P4** — Continue web framework track (layout primitives)

---

## Check Matrix

| Check | Group | Description | Status |
|---|---|---|---|
| NET-GLOB-1 | NET-GLOB | exact match: api.example.com ⊆ {api.example.com} | PASS |
| NET-GLOB-2 | NET-GLOB | *.example.com is opaque literal; api.example.com ⊄ it | PASS |
| NET-GLOB-3 | NET-GLOB | *.example.com ⊆ {*.example.com} (same literal) | PASS |
| NET-GLOB-4 | NET-GLOB | api.example.com ⊆ {*} (full wildcard) | PASS |
| NET-GLOB-5 | NET-GLOB | multi-host child, partial parent — fails | PASS |
| NET-GLOB-6 | NET-GLOB | check_policy_net2 with * — any host passes | PASS |
| NET-GLOB-7 | NET-GLOB | check_policy_net2 explicit host — wrong host fails | PASS |
| NET-GLOB-8 | NET-GLOB | delegation child [api] under parent [*.example.com] → HOST-ESCAPE | PASS |
| NET-GLOB-9 | NET-GLOB | delegation child [*.example.com] under parent [*] → valid | PASS |
| NET-BOTH-1 | NET-BOTH-DIR | direction_both fixture has both bits true | PASS |
| NET-BOTH-2 | NET-BOTH-DIR | compose(connect_only, listen_only) → both bits false | PASS |
| NET-BOTH-3 | NET-BOTH-DIR | compose(both, connect_only) → connect result | PASS |
| NET-BOTH-4 | NET-BOTH-DIR | compose(both, listen_only) → listen result | PASS |
| NET-BOTH-5 | NET-BOTH-DIR | valid_delegation?(both, connect_child) → valid | PASS |
| NET-BOTH-6 | NET-BOTH-DIR | valid_delegation?(both, listen_child) → valid | PASS |
| NET-BOTH-7 | NET-BOTH-DIR | valid_delegation?(connect, listen_child) → PERMISSION-ESCALATION | PASS |
| NET-BOTH-8 | NET-BOTH-DIR | compose(both, both) → both still true | PASS |
| NET-CHAIN-1 | NET-CHAIN | G1→G2 valid | PASS |
| NET-CHAIN-2 | NET-CHAIN | G2→G3 valid | PASS |
| NET-CHAIN-3 | NET-CHAIN | Transitivity: G1→G3 direct valid | PASS |
| NET-CHAIN-4 | NET-CHAIN | compose(G1,G2)→G3 valid | PASS |
| NET-CHAIN-5 | NET-CHAIN | G3 port escape under G2 → PORT-ESCAPE | PASS |
| NET-CHAIN-6 | NET-CHAIN | G3 proto escalation under G2 → PROTOCOL-ESCALATION | PASS |
| NET-CHAIN-7 | NET-CHAIN | G2(no TLS)→G3(tls) TLS hardening valid | PASS |
| NET-CHAIN-8 | NET-CHAIN | G3(tls)→G2(no tls) → TLS-DOWNGRADE | PASS |
| NET-CHAIN-9 | NET-CHAIN | compose associativity for port/protocol/connect | PASS |
| NET-CHAIN-10 | NET-CHAIN | compose reduces port scope at each hop | PASS |
| NET-BIND-1 | NET-BIND | null parent → any child bind valid (Condition 8) | PASS |
| NET-BIND-2 | NET-BIND | same bind_address → valid | PASS |
| NET-BIND-3 | NET-BIND | different non-null bind → BIND-ESCALATION | PASS |
| NET-BIND-4 | NET-BIND | null parent + non-null child → Condition 8 NOT fired | PASS |
| NET-BIND-5 | NET-BIND | non-null parent + null child → Condition 8 NOT fired | PASS |
| NET-BIND-6 | NET-BIND | BIND-ESCALATION is the only violation in diff-bind case | PASS |
| NET-WILD-1 | NET-WILD | wildcard+no-loop: external host passes both checks | PASS |
| NET-WILD-2 | NET-WILD | wildcard+loopback: 127.0.0.1 passes both checks | PASS |
| NET-WILD-3 | NET-WILD | wildcard+loopback: external passes NET-2, fails NET-1 | PASS |
| NET-WILD-4 | NET-WILD | NET-1 fires E-NET-LOOPBACK-VIOLATION for external | PASS |
| NET-WILD-5 | NET-WILD | loopback parent → no-loop child: LOOPBACK-ESCAPE | PASS |
| NET-WILD-6 | NET-WILD | loopback parent → loopback child: Condition 4 valid | PASS |
| NET-STABLE-1 | NET-STABLE | NDA module responds to key methods | PASS |
| NET-STABLE-2 | NET-STABLE | All 7 delegation violation codes producible | PASS |
| NET-STABLE-3 | NET-STABLE | No real socket refs in proof runner | PASS |
| NET-STABLE-4 | NET-STABLE | igniter-lang repo untouched | PASS |
| NET-STABLE-5 | NET-STABLE | P5 independent of P3 FFI stub | PASS |
