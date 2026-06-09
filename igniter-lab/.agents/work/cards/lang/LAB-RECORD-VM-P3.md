# LAB-RECORD-VM-P3: Nested Record Field Values

**Category:** lang
**Track:** `lab-record-vm-nested-record-field-values-proof-v0`
**Status:** CLOSED / PROVED — 49/49 PASS
**Date closed:** 2026-06-09
**Agent:** Igniter-Lang Implementation Agent
**Role:** implementation-agent
**Route:** EXPERIMENTAL / LAB-ONLY

---

## Depends on

- LAB-RECORD-VM-P2 (dispatched record field access — 42/42)
- LAB-RECORD-VM-P1 (VM record construction and serialization — 43/43)
- LAB-RACK-P13 (nominal record typechecking — 47/47)
- LAB-SIDEKIQ-P4 (JobReceipt schema — 46/46)

---

## Goal

Prove that a record field can hold another record, and that chained field access
expressions like `outer.inner.field` work end-to-end through typechecking,
SemanticIR, bytecode compilation, and VM execution.

---

## Key Finding: One Targeted Compiler Line

P3 required the smallest possible change: one line in compiler.rs. The typechecker
already handled chained access recursively. The VM already built nested records
correctly. `OP_GET_FIELD (0x22)` from P2 was reused unchanged.

| Component | Change |
|---|---|
| `igniter-vm/src/compiler.rs` | Replace `Err("Unsupported object type...")` with `compile_expr(object)? + OP_GET_FIELD(field)` |

Root cause: the compiler's `"field_access"` fallback returned an error when `object`
was not a `"ref"` node — i.e., when `object` was itself a `"field_access"` for chaining.
The fix adds one recursive call to handle the general case.

---

## Explicit Answers

| Question | Answer |
|---|---|
| Nested record types as field values proved | ✅ YES — `HeaderInfo` in `ResponseEnvelope`; `JobMeta` in `JobEnvelope` |
| Chained field access end-to-end (`outer.inner.field`) | ✅ YES — `envelope.headers.content_type → "text/plain"`, `envelope.meta.priority → 5` |
| Typechecker changes required | ❌ NO — already handles chaining recursively |
| New VM opcodes required | ❌ NO — `OP_GET_FIELD (0x22)` from P2 reused |
| Nested record serialization deterministic | ✅ YES — `BTreeMap` at every level |
| Missing inner field safe | ✅ YES — OOF-P1 at compile time naming the inner type |
| Direct local nested access on Unknown records | ✅ FAIL-CLOSED — OOF-P1 |
| Non-record intermediate chain (`Integer.field`) safe | ✅ YES — OOF-P1 at compile time |
| Tier 2 + chained field access safe | ✅ YES — OOF-P1 `Unknown.headers` |
| Creates canon/runtime/public authority | ❌ NO |

---

## Scope

### Proved in P3

- `EnvelopeBuilder` constructs `ResponseEnvelope` with `HeaderInfo` nested field
- `ContentTypeReader` reads `envelope.headers.content_type` (String) via chained access
- `CacheControlReader` reads `envelope.headers.cache_control` (String) via chained access
- `JobEnvelopeBuilder` constructs `JobEnvelope` with `JobMeta` nested field
- `PriorityReader` reads `envelope.meta.priority` (Integer) via chained access
- `QueueReader` reads `envelope.meta.queue` (String) via chained access
- Direct local nested access on Unknown-typed record → OOF-P1 at compile time
- Missing inner field → OOF-P1 naming the inner record type
- Non-record intermediate chain (`Integer.something`) → OOF-P1 at compile time
- Tier 2 variable callee + chained field access → OOF-P1 at compile time

### Not opened in P3

- Three-level chained field access (`a.b.c.d`)
- Tier 2 dynamic callee + chained field access at runtime
- Local record literal type annotation enabling direct nested access
- Enum/status type system
- Array-valued fields

---

## Deliverables

| File | Status |
|---|---|
| `igniter-view-engine/fixtures/rack_core/nested_record_field_values.ig` | ✅ Written |
| `igniter-view-engine/proofs/verify_record_vm_nested_records.rb` | ✅ 49/49 PASS |
| `igniter-vm/src/compiler.rs` | ✅ `"field_access"` fallback fixed (P3 change, one line) |
| `lab-docs/lang/lab-record-vm-nested-record-field-values-proof-v0.md` | ✅ Written |
| `.agents/work/cards/lang/LAB-RECORD-VM-P3.md` (this file) | ✅ Authoritative |
| `.agents/portfolio-index.md` updated | ✅ P3 row added |

---

## P4 Recommendation

**Three-level chained field access or Tier 2 type resolution** — the next natural
extensions from P3. Either prove `a.b.c.d` (three levels of nesting), or explore
whether Tier 2 dynamic callees can be given named types at the call site to enable
chained field access.

---

## Boundary

Lab-only. No Rack compatibility claim. No Sidekiq compatibility claim. No canon grammar
change. No production runtime authority. No public API stability. `call_contract` is
lab-only. `OP_GET_FIELD` is lab-only VM instrumentation with no public bytecode
stability. The compiler change is inside `igniter-lab/igniter-vm/`, not in
`igniter-lang` or `igniter-compiler` canon code.
