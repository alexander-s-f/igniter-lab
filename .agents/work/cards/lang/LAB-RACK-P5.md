# LAB-RACK-P5

**Card ID:** LAB-RACK-P5
**Category:** lang / web
**Track:** lab-rack-vm-stdlib-text-alignment-v0
**Route:** EXPERIMENTAL / LAB-ONLY
**Date:** 2026-06-08
**Status:** ✅ DONE — 20/20 PASS

---

## D — Deliverables

- `igniter-vm/src/vm.rs` — **3 new OP_CALL cases added** (stdlib.text.* aliases)
- `igniter-view-engine/proofs/verify_p5_vm_stdlib_text.rb` — **main deliverable, 20/20 PASS**
- `.agents/work/cards/lang/LAB-RACK-P5.md` (this receipt)

---

## S — Summary

Added 3 `stdlib.text.*` namespaced function cases to the VM OP_CALL handler in
`igniter-vm/src/vm.rs`, closing the compiler-VM namespace mismatch gap found in
LAB-RACK-P4.

**vm.rs changes:**
```rust
"stdlib.text.starts_with" => { /* same as bare "starts_with" */ }
"stdlib.text.split"       => { /* same as bare "split" */ }
"stdlib.text.byte_length" => { /* same as bare "length" (byte count) */ }
```

**Result:** LAB-RACK-P4 contracts now execute end-to-end on the VM:

| Route | Expected | VM Result |
|-------|----------|-----------|
| GET / | 200 | 200 ✅ |
| GET /articles/42 | 200 | 200 ✅ |
| POST /articles | 201 | 201 ✅ |
| GET /missing | 404 | 404 ✅ |
| POST /articles/42 | 405 | 405 ✅ |
| extract /articles/42 | "42" | "42" ✅ |
| extract /articles/99 | "99" | "99" ✅ |

---

## Proof Matrix Coverage

| Item | Status |
|------|--------|
| P5-1: Compile regression (both contracts still ok) | ✅ 2 checks |
| P5-2: vm.rs source confirms 3 new stdlib.text.* cases | ✅ 4 checks |
| P5-3..7: 5 route dispatch cases execute correctly on VM | ✅ 5 checks |
| P5-8: Path param extraction executes correctly on VM | ✅ 3 checks |
| P5-9..11: Closed-surface scan | ✅ 4 checks |
| P5-12: Gap packet updated (vm_stdlib_text closed; string_equality open) | ✅ 2 checks |

---

## Gap closed

| Gap (from P4) | Status |
|---------------|--------|
| VM `stdlib.text.*` namespace mismatch | ✅ **CLOSED** — 3 cases added to vm.rs |

## Still open

| Gap | Path |
|-----|------|
| TypeChecker `==` and `<` (OOF-TY0) | Separate TypeChecker card |
| VM entrypoint selector (contracts[0] only) | VM extension card |
| ContractRef runtime dispatch | VM extension card |

---

## Next route recommendation

**LAB-RACK-P6: TypeChecker == and < alignment**
Unblock string equality (`path == "/articles"`) and less-than comparison
(`byte_length(path) < N`) in the TypeChecker. This would allow the route
dispatch contract to use idiomatic equality checks instead of `starts_with`
workarounds, and enable route pattern matching with bounded length checks.
