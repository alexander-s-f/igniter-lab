# LAB-IGNITER-PACKAGE-REMOTE-TRUST-READINESS-P22 — verified artifact trust for future remote nodes

Status: OPEN
Lane: package / remote substrate / trust
Type: readiness / design
Delegation code: OPUS-IGNITER-PACKAGE-REMOTE-TRUST-READINESS-P22
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

The package manager v0 is now local-first and CI-trustable:

- local package dependencies;
- lock/verify;
- strict integrity;
- exports / closed default;
- transitive graph;
- source package archive pack/verify.

Home-lab remote-node archaeology reframed "remote contract" as substrate/runtime + host capability +
control-plane. A future node should not execute arbitrary source just because a peer says so. It should execute
a verified artifact or package bundle pinned by content/provenance.

This card designs that trust seam. It does **not** implement networking, registry, semver, or node deployment.

## Goal

Design how a future remote node verifies an Igniter package/artifact before executing it.

Questions:

- What exactly is transferred?
  - `.igpkg` archive?
  - lockfile + sources?
  - compiled `.igapp`?
  - both source and compiled artifact?
- What is trusted?
  - content hash;
  - lockfile;
  - compiler/stdlib version;
  - exports/integrity;
  - signature later?
- What does a node prove before accepting work?

## Verify first

Read live surfaces:

- `lab-docs/lang/lab-igniter-package-transitive-graph-p14-v0.md`
- `lab-docs/lang/lab-igniter-package-transitive-graph-ci-p15-v0.md` if present
- `lab-docs/lang/lab-igniter-package-archive-readiness-p21-v0.md`
- package lock/verify/pack code in `lang/igniter-compiler/src/project.rs` and CLI code
- tests for `igc lock`, `igc verify --strict`, and package archive pack/verify
- current card(s) around package archive / source package if present
- from `../igniter-home-lab`: `docs/research/remote-node-substrate-readiness.md`

Live code wins over this card. If an archive feature is only readiness and not implemented, say so.

## Questions to answer

1. What is the smallest artifact a remote node can verify today?
2. Is source archive verification enough for v0, or must compiled `.igapp` be included?
3. How does `verify --strict` apply on a node with no registry?
4. What provenance fields must travel with the artifact?
   - package name/version;
   - source hash;
   - lock hash;
   - compiler version;
   - stdlib version;
   - exports policy;
   - entry contract.
5. What is explicitly host/control-plane owned?
   - node identity;
   - authorization;
   - transport;
   - admission policy.
6. What should a node refuse?
   - missing lock;
   - stale lock;
   - integrity faults;
   - compiler/stdver drift;
   - unsigned artifact if a signing policy is enabled later.
7. How do receipts record artifact identity?
8. How does this connect to distributed Kuramoto?
   - all nodes run the same verified `NodeTick` package;
   - topology/seed is separate runtime config;
   - result lineage includes artifact digest.
9. What belongs to a later registry/semver wave?
10. What is the first implementation proof?

## Design constraints

- No registry.
- No semver solver.
- No remote network calls.
- No deployment changes.
- No signatures unless they are explicitly scoped as future work.
- Do not move execution authority into `.ig`.
- Keep package trust content-addressed and local-first.

## Acceptance

- [ ] Packet maps current package primitives to remote-node trust.
- [ ] Packet states whether `.igpkg` source archive is enough for v0.
- [ ] Packet defines required provenance fields.
- [ ] Packet defines node refusal conditions.
- [ ] Packet explains how `verify --strict` is used by a remote node.
- [ ] Packet separates package trust from transport/auth/control-plane.
- [ ] Packet connects to network Kuramoto artifact lineage.
- [ ] Packet names first implementation proof and acceptance matrix.
- [ ] No code changes.
- [ ] No registry/semver claim.
- [ ] No remote/deploy changes.
- [ ] Proof doc written under `lab-docs/lang/`.
- [ ] `git diff --check` clean.

## Suggested output

`lab-docs/lang/lab-igniter-package-remote-trust-readiness-p22-v0.md`

## Likely next card

`LAB-IGNITER-PACKAGE-REMOTE-TRUST-P23` — local proof that a "node" process verifies a packed package/archive
with `verify --strict`, records artifact identity in a receipt-like result, and refuses tampered/stale input.
