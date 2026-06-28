# LAB-IGNITER-COMPILER-LOCK-DEFAULT-POLICY-READINESS-P4

Status: OPEN
Route: standard / main-audit / compiler / package trust policy
Skill: idd-agent-protocol
Depends-On: `LAB-IGNITER-COMPILER-LOCK-ON-BUILD-P2`,
`LAB-IGNITER-COMPILER-DEP-PATH-CONTAINMENT-P3`

## Goal

Decide the default policy for project compile lock enforcement now that locked
compile and dependency path containment both exist.

This is audit-control-board row A12 follow-up. It is readiness/policy first:
do not flip defaults in this card unless the analysis proves a tiny safe
implementation and explicitly closes the decision.

## Current Authority

Live source wins. Read first:

- `lab-docs/lang/lab-audit-control-board-v1.md`
- `lab-docs/lang/lab-igniter-compiler-dep-path-containment-p3-v0.md`
- package/workspace implemented surface if present
- `lang/igniter-compiler/src/main.rs`
- `lang/igniter-compiler/src/project.rs`
- `lang/igniter-compiler/tests/package_lockfile_cli_tests.rs`
- `lang/igniter-compiler/tests/package_workspace_tests.rs`

Known live facts to re-verify:

- `compile --project-root ... --locked` / `--frozen` exists and fails before
  emit on missing/stale/integrity-bad locks;
- local dependency paths are contained under the workspace trust root;
- current default compile behavior may still allow unlocked project compile.

## Scope

Allowed:

- Produce a policy/readiness packet comparing default-on lock enforcement,
  warning-only default, explicit `--locked`, and dev escape hatch.
- Run smoke tests to prove current behavior.
- If and only if the safest decision is trivial and evidence is complete, make
  the smallest CLI/doc/test change required by the packet.
- Name exact next implementation card if policy is not implemented here.

Closed:

- No registry/semver/signing implementation.
- No remote source trust implementation.
- No package solver.
- No changes to `.ig` language semantics.
- No broad project-file migration.

## Questions To Answer

1. What is the current default project compile behavior?
2. Should project compile require a current lock by default?
3. Is there a local-dev escape hatch, and what is it called?
4. How does this interact with `igc lock --frozen` and CI?
5. What diagnostics distinguish missing lock, stale lock, integrity fault, and
   explicit unlocked mode?
6. Which examples/fixtures would break if default-on changed today?

## Acceptance

- [ ] Current default behavior is verified by live CLI tests.
- [ ] At least three policy alternatives are compared.
- [ ] Recommendation is explicit: implement now, implement later, or keep
      explicit `--locked` for now.
- [ ] CI/dev/operator consequences are named.
- [ ] If code changes are made, package lockfile/workspace tests are green.
- [ ] If no code changes are made, a concrete next card is named.
- [ ] `git diff --check` passes.
- [ ] Card is closed with a concise report.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test package_lockfile_cli_tests
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test package_workspace_tests
git diff --check
```

Also run targeted CLI smoke commands in a tempdir/fixture copy, not by mutating
committed fixtures in place.

## Required Packet

Create:

```text
lab-docs/lang/lab-igniter-compiler-lock-default-policy-readiness-p4-v0.md
```

Packet must include:

- current behavior transcript;
- policy alternatives;
- recommendation;
- exact implementation card if not implemented here.

