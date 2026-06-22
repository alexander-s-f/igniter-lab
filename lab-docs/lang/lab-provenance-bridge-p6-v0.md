# LAB-PROVENANCE-BRIDGE-P6 readiness

Date: 2026-06-22
Status: READINESS - missing admitted-package runner input seam
Scope: igniter-lab evidence only; this does not change canon language authority.

## Decision

Do not wire `artifact_digest` in this slice. The experiment provenance schema already
has the field, and package admission already emits artifact identity, but the current
experiment runner does not receive an admitted package receipt or package input.

Adding a free-form `--artifact-digest` flag would fabricate trust at the runner
boundary. The next implementation needs an admitted-package input contract that gets
the digest from verified/admitted metadata.

## Live evidence

Verify-first commands run from `igniter-lab`:

```text
rg -n "artifact_digest|build_provenance_json|provenance" lang/igniter-vm/src lang/igniter-vm/tests lang/igniter-compiler/src
rg -n "admit|verify_archive|igpkg|manifest.digest|artifact_digest" lang/igniter-compiler/src lang/igniter-compiler/tests
```

Current runner entrypoint:

- `lang/igniter-vm/src/experiment.rs:157-162` dispatches only
  `igniter-vm experiment kuramoto`.
- `lang/igniter-vm/src/experiment.rs:176-216` accepts `--kernel`, `--compiler`,
  `--out`, `--entry`, `--config`, and `--cli-vm`. There is no package, admission
  receipt, or artifact metadata argument.
- `lang/igniter-vm/src/experiment.rs:248-287` validates a plain kernel path,
  hashes it, compiles source to `kernel.igapp`, loads Semantic IR, then runs the
  in-process simulation.
- `lang/igniter-vm/src/experiment.rs:961-971` calls
  `build_provenance_json(..., None)` and writes `provenance.json`.
- `lang/igniter-vm/src/experiment.rs:1124-1145` defines the provenance schema
  with optional `artifact_digest`.

Package admission output that should carry digest:

- `lang/igniter-compiler/src/project.rs:1411-1490` implements `admit_archive`.
- `lang/igniter-compiler/src/project.rs:1480-1489` emits
  `kind: "igniter_package_admission"`, `accepted`, `artifact_digest`,
  `lock_digest`, `compiler_version`, `stdlib_version`, `entry`,
  `entry_contract`, and `refusals`.
- `lang/igniter-compiler/tests/package_lockfile_cli_tests.rs:515-530`
  asserts admitted packages carry a `sha256:` `artifact_digest`.

Targeted checks:

```text
cargo test provenance_json_shape_is_stable --lib
```

Result: 1 passed; verifies the current VM provenance shape keeps
`artifact_digest: null` for plain/unpackaged experiments.

```text
cargo test --test package_lockfile_cli_tests cli_admit_clean_accepted -- --nocapture
```

Result: 1 passed; verifies package admission emits `artifact_digest` on the
accepted receipt.

## Missing seam

The bridge is not a field-shape problem. It is an input-contract problem:

- VM runner source is plain `--kernel <path>`.
- Compiler package admission is a separate CLI/project layer receipt.
- No current path proves that the kernel being executed came from the admitted
  `.igpkg` whose digest would be copied into provenance.

Therefore the runner cannot safely populate `artifact_digest` today without
inventing or trusting an out-of-band value.

## Smallest next implementation card

```text
Card: LAB-PROVENANCE-BRIDGE-P7 - admitted package input for experiment provenance
Status: READY
Lane: package trust / experiment runner
Type: implementation
Skill: idd-agent-protocol

Goal:
Add a local admitted-package experiment input mode that lets
`igniter-vm experiment kuramoto` execute a kernel sourced from an admitted
`.igpkg` and copy the admission receipt's `artifact_digest` into
`provenance.json`.

Allowed:
- Add an explicit runner input such as `--package <file.igpkg>` plus admission
  policy flags, or an equivalent typed admission-receipt path if it also binds
  the executed kernel to the unpacked package tree.
- Reuse existing compiler package admission/verification primitives or a small
  shared helper; do not change digest algorithms.
- Preserve plain `--kernel` behavior with `artifact_digest: null`.
- Add tests proving plain source emits null and admitted package execution emits
  the receipt digest.

Closed:
- No registry, signing, networking, remote admission, or deploy semantics.
- No raw free-form `--artifact-digest` that can be detached from verified
  admission metadata.
- No canon-language authority change from this lab evidence.

Acceptance:
- The executed kernel is demonstrably loaded from the admitted package tree.
- Refused admission does not run the experiment.
- Accepted admission writes the exact `artifact_digest` from the receipt into
  experiment `provenance.json`.
- `git diff --check` clean.
```
