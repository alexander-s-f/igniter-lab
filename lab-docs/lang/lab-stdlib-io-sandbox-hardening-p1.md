# LAB-STDLIB-IO-SANDBOX-HARDENING-P1

Status: DONE
Date: 2026-06-27
Lane: igniter-lab / stdlib / IO / foundation-hardening

## Authority

Live `lang/igniter-stdlib` source and tests decide this lab behavior. The
foundation audit docs were used as evidence only. This is not a canon language
claim and does not promote the experimental IO surface to production authority.

`lang/igniter-stdlib/IMPLEMENTED_SURFACE.md` was requested by the card but is
not present in the current checkout; live source/tests were used instead.

## Sandbox Policy

The stdlib IO validator now treats `IOCapability.sandbox_dir` as the configured
sandbox root, resolves it to a canonical filesystem path, and checks relative
operation targets with component-aware `starts_with` containment. The previous
hardcoded substring gate for `/igniter-stdlib/out` was removed.

For writes, validation now:

- rejects lexical `..` escapes after joining against the canonical sandbox;
- rejects existing symlink components in the write target path;
- canonicalizes existing write parents and requires them to remain under the
  canonical sandbox;
- validates the nearest existing ancestor for not-yet-created parent paths;
- re-validates after parent directory creation and before writing.

## Platform Note

The crate remains dependency-free and avoids platform-specific open flags in
this slice. Symlink refusal is implemented with `symlink_metadata` plus canonical
parent checks. The Unix tests cover both an existing symlink target and an absent
target under a symlinked parent. A future machine-routed IO implementation can
add stronger OS-level no-follow/open semantics.

## Verification

Commands run from `lang/igniter-stdlib` unless noted otherwise:

```text
cargo test --test io_sandbox_hardening_tests
cargo test
git diff --check
```

Results:

```text
cargo test --test io_sandbox_hardening_tests
  4 passed; 0 failed

cargo test
  lib tests: 0 passed; 0 failed
  decimal_money_safe_tests: 4 passed; 0 failed
  io_sandbox_hardening_tests: 4 passed; 0 failed
  regexp_engine_proof_tests: 11 passed; 0 failed
  doc tests: 0 passed; 0 failed

git diff --check
  PASS
```

## Follow-Up

Route experimental `stdlib.IO` through the hardened `igniter-machine` capability
executor in a separate readiness slice. This card only hardens the current
stdlib lab surface locally.
