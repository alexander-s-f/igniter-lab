# lab-igniter-package-manager-research-round1-v0 — Gemini package research, curated first round

**Status:** CURATED ROUND-1 RESEARCH SUMMARY  
**Date:** 2026-06-18  
**Authority:** Lab research only. This is not a package spec, not canon, and not an implementation
authorization. It summarizes Gemini background research and identifies what Opus should validate next.

## Inputs reviewed

Gemini produced five shard reports plus one synthesis report:

- `lab-igniter-package-research-cargo-go-gemini-p1-v0.md`
- `lab-igniter-package-research-js-py-deno-gemini-p1-v0.md`
- `lab-igniter-package-research-ruby-rails-gemini-p1-v0.md`
- `lab-igniter-package-research-oci-wasm-terraform-gemini-p1-v0.md`
- `lab-igniter-package-research-igniter-artifacts-gemini-p1-v0.md`
- `lab-igniter-package-research-synthesis-gemini-p1-v0.md`

All outputs stayed research-only: no code, no registry, no package spec, no canon promotion.

## Round-1 consensus

The reports converge on a strong v0 direction:

```text
local workspace packages
  + explicit path dependencies
  + content-addressed lock/provenance
  + projection dialects as pure lowering inputs
  + generated artifacts inspectable
  + no install scripts / no hidden hooks
  + host-owned capabilities and secrets
  + registry and version solver deferred
```

This fits the current Igniter shape better than a registry-first package manager. The package manager
should start as a **local workspace resolver and lock/provenance layer**, not as a publishing system.

## Strong design signals

1. **Package identity should be two-layered.** Human-readable scoped name for DX; content digest as
   the reproducibility anchor in the lockfile.
2. **Package contents should distinguish source, projection source, generated output, and compiled
   artifact.** `.igweb`/`.igv` remain projection dialects; they do not become runtime authority.
3. **Lockfile must pin more than dependencies.** It should eventually pin package content digests,
   compiler version, stdlib version, lowerer version, and generated artifact hashes.
4. **Install scripts should be absent in v0.** Any lowering/build work must be a known compiler/tool
   step, not package-provided executable authority.
5. **Capabilities are declarations, not credentials.** Packages may declare abstract needs
   (`Postgres.Read`, HTTP outbound, etc.); the host binds actual secrets/endpoints.
6. **Registry is later.** v0 should work with local relative paths and explicit workspace config.
7. **Version solving is later.** Gemini initially over-indexed on MVS; curation downgrades it to a
   future option. Local v0 should avoid SAT and MVS entirely.

## Curation notes

I made small hygiene edits before committing this round:

- removed absolute `file://` links from reports;
- changed "compile-clean" language for markdown reports to "present as research docs";
- downgraded MVS from v0 recommendation to later remote/versioned-package research;
- changed hardcoded `sha256` examples to generic `<digest>` where the algorithm is not yet chosen;
- marked the Igniter-artifacts card closed after Gemini wrote its report.

## Open questions for Opus validation

1. **Generated artifacts policy:** Should generated `.ig`/JSON be committed by default, or can a
   deterministic build cache plus source map be enough?
2. **Lockfile granularity:** One lockfile per workspace, per package, or both?
3. **Digest algorithm:** Use existing project digest helper if present, BLAKE3 for speed, or SHA-256
   for ecosystem familiarity?
4. **Namespace mapping:** Should package names force module namespace prefixes, or only validate
   declared modules against dependency ownership?
5. **Direct dependency enforcement:** How exactly does the compiler reject phantom transitive imports?
6. **Compiled artifact packaging:** Is `.igapp` part of the package, a build cache, or a release
   artifact only?
7. **Projection dialect order:** How to prevent nested/generated dialect cycles while allowing `.igweb`
   and `.igv` in the same workspace?
8. **Capability manifest shape:** What is the minimal field set for declaring host capabilities without
   leaking credentials or deployment topology?

## Recommended next Opus card

`LAB-IGNITER-PACKAGE-ROUND1-OPUS-VALIDATION-P2`

Goal: verify Gemini's round-1 conclusions against live Igniter surfaces and primary-source ecosystem
facts, then either approve or revise the smallest implementation card.

Acceptance sketch:

- read all six Gemini reports plus this curation;
- verify live Igniter surfaces (`project.rs`, projection dialects, server/machine surfaces);
- mark each strong design signal as `accept`, `revise`, or `reject`;
- produce one validation packet;
- name the next implementation card, likely a local workspace resolver/lockfile slice;
- no code.

## Candidate implementation after validation

If Opus validates the direction, the first implementation slice should be smaller than "package
manager":

`LAB-IGNITER-PACKAGE-WORKSPACE-RESOLVER-P3`

Likely scope:

- parse a tiny workspace/dependencies config;
- add local path dependency roots to project compilation;
- validate duplicate module ownership;
- no registry, no version solver, no install hooks, no lockfile yet unless deliberately chosen.

The lock/provenance slice should follow only after the workspace resolver shape is grounded in live
compiler behavior.
