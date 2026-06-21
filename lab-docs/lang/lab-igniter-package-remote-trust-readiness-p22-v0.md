# lab-igniter-package-remote-trust-readiness-p22-v0 — verified-artifact trust for future remote nodes

**Card:** `LAB-IGNITER-PACKAGE-REMOTE-TRUST-READINESS-P22` · **Delegation:** `OPUS-IGNITER-PACKAGE-REMOTE-TRUST-READINESS-P22`
**Status:** READINESS / DESIGN (v0) — maps the existing package primitives to a future remote node's trust
gate, decides `.igpkg` source archive is enough for v0, and names the small gaps + the first implementation
proof. **No code. No registry/semver/network/deploy/signing.**

---

## 1. Executive summary

The trust seam is **~90% already built** and the architecture is **already settled** by the home-lab
archaeology: a remote node must run a **verified artifact**, never arbitrary peer source. The home-lab research
(`docs/research/remote-node-substrate-readiness.md`) concludes — *"remote contract" is a substrate / runtime +
host-capability + control-plane concern; the package layer is **content-addressed `.igpkg` + `verify --strict`
+ provenance**; the contract stays pure + local.* The live `.igpkg` (P22, now **implemented** — the research
doc predates it) already carries content digest + compiler/stdlib version + lockfile + closed-surfaces, and
`verify_archive` already recomputes the digest + runs `check_workspace_integrity` offline.

So v0 is: **a remote node receives a `.igpkg` by any transport, verifies it locally (content digest + lock
parity + integrity + toolchain match), records the artifact digest in its receipt, and refuses
tampered/stale/drifted input — before executing.** Three small gaps remain (lock-parity, toolchain-match,
artifact-identity output); they are the P23 implementation. Trust is **content-addressed and local-first**;
identity / authorization / transport / admission stay in the host + control-plane, never in the package or
`.ig`.

## 2. Map: remote-node trust need → existing package primitive (live code wins)

| Trust need | Existing primitive | State |
|---|---|---|
| smallest verifiable artifact (Q1) | **`.igpkg`** source archive — `pack_archive`/`verify_archive` (P22) | **implemented** |
| content trust | whole-tree `sha256` `manifest.digest` (P22) + per-package `dependency_digest` (P3/P10) | implemented |
| integrity without a registry (Q3) | `verify_archive` → unpack → `check_workspace_integrity` (OOF-IMP4/6/7/8/9, the `verify --strict` engine, P8/P14/P16) | implemented |
| toolchain provenance | `manifest.compiler_version` + `manifest.stdlib_version` (mirror the lock toolchain block, P5/P6) | implemented (carried; not yet *checked* against the node) |
| lock provenance | `igniter.lock` travels as a packed file → folded into the tree digest (P22) | carried (parity not yet *re-checked* on the node) |
| exports / scope policy | each package's `igniter.toml` `[exports]` is packed + re-enforced by `check_workspace_integrity` | implemented |
| "same code on every node" (Q8) | identical `.igpkg` ⇒ identical `manifest.digest` | implemented |

**Conclusion:** content + integrity + most provenance already verify offline. The remote-trust card is a
**mapping + three small additions**, not a new subsystem.

## 3. Decisions

### Q2 — source `.igpkg` is enough for v0 (no compiled `.igapp` in the trust path)
A node verifies the **source** `.igpkg`, then **compiles locally** and runs. It never trusts a foreign binary
— matching the RubyGems lesson ("never trust foreign compiled artifacts; native belongs at the host layer").
A compiled `.igapp` is a *deploy/perf* artifact (`.igbundle`, home-lab), **not** a trust requirement.
Re-deriving the artifact deterministically on the node is the stronger guarantee.

### Q4 — provenance fields that must travel
Already in the manifest: `format`, `kind`, `name`, **`digest`** (content), **`compiler_version`**,
**`stdlib_version`**, `entry` (entry *package*), `lockfile`, `closed_surfaces`, `signature: null`. The lock
(transitive closure + toolchain) travels as a packed file. **Two additions for the remote story (P23):**
- **`lock_digest`** — surface the packed lock's digest as a top-level field (it is *inside* the tree digest
  today, but a node wants it explicitly for receipts/lineage).
- **`entry_contract`** (a.k.a. `entrypoints`) — the manifest names the entry *package* but not the entry
  *contract* (e.g. `NodeTick`); the Kuramoto story needs "run **this** contract". Optional in v0; recommended.

### Q5 — host / control-plane owned (NEVER in package or `.ig`)
**Node identity, authorization, transport, admission policy.** The package layer proves *what the code is*
(content + integrity + provenance); it does **not** decide *who* may send work, *how* it arrives, or *whether*
this node accepts it. Transport = a passport-gated host capability with a receipt (igniter-machine effect
host); admission/identity = control-plane. (Home-lab research §3 layering.)

### Q6 — node refusal conditions
A node must refuse and not execute when:
1. **digest mismatch** — recomputed tree digest ≠ `manifest.digest` (tamper). *Implemented* (`digest_ok`).
2. **integrity fault** — `OOF-IMP4/6/7/8/9` on the unpacked tree. *Implemented* (`integrity`).
3. **missing lock** — `manifest.lockfile == null` under a strict node policy. *Gap (policy flag).*
4. **stale lock** — the packed `igniter.lock` does not match the packed sources (recompute `workspace_lock`
   on the unpacked tree → any drift). **Gap → P23** (`verify_archive` does not run `verify_lock` today).
5. **toolchain drift** — `manifest.compiler_version`/`stdlib_version` ≠ the node's own. **Gap → P23**
   (carried but not compared to the local toolchain).
6. **unsigned** — only if/when a signing policy is enabled (future; `signature` slot reserved).

### Q7 — receipts record artifact identity
A node's execution receipt must include `{ artifact_digest = manifest.digest, compiler_version,
stdlib_version, entry_contract }` — "result lineage includes the artifact digest" (research §5). Receipts are
an **igniter-machine effect** concern; the package layer *exposes* these fields (P23 returns them as a
verify-result), the runtime *records* them.

### Q8 — distributed Kuramoto
- every node pulls + verifies the **same** `.igpkg` for the `NodeTick` contract → **same `manifest.digest`**;
- topology / seed / neighbor set = **separate runtime config**, never in the package (the contract is pure,
  decides next state from inputs only);
- each node's result lineage carries the artifact digest → the run is **reproducible + attributable** to an
  exact verified artifact. The package is the unit of "same proven code everywhere."

### Q9 — later registry/semver wave
Naming → version resolution, a registry index + remote fetch, signing + keys/trust roots, admission policy,
multi-version coexistence. v0 transfers the artifact by **any** means (copy / the transport capability) and
verifies **locally** — content-addressed, no registry.

## 4. First implementation proof — `LAB-IGNITER-PACKAGE-REMOTE-TRUST-P23`

A **local** "node-admission" proof (no networking): a function/CLI a future node runtime calls to decide
*accept / refuse* a packed `.igpkg`, recording artifact identity.

**Implementation (`project.rs` + `main.rs`, reuse P22):**
- Extend `verify_archive` (or add `admit_archive`) to ALSO: (a) **lock parity** — recompute `workspace_lock`
  on the unpacked tree and diff against the packed `igniter.lock` (stale-lock → refuse); (b) **toolchain
  match** — compare `manifest.compiler_version`/`stdlib_version` to the local `env!("CARGO_PKG_VERSION")` /
  `STDLIB_VERSION` (drift → refuse); (c) emit a **receipt-like result** `{ accepted, artifact_digest,
  lock_digest, compiler_version, stdlib_version, entry, refusals: [...] }`.
- Add `lock_digest` (+ optional `entry_contract`) to the pack manifest.
- CLI: `igc package admit <file.igpkg> [--require-lock] [--match-toolchain]` (or fold flags into `verify`).

**Acceptance matrix (P23):**
- [ ] Clean archive → `accepted: true`, receipt carries `artifact_digest` + `compiler_version` + `stdlib_version`.
- [ ] Tampered byte → refuse, reason `digest_mismatch`.
- [ ] Integrity fault (phantom/non-export/cycle/missing) → refuse, reason `integrity` + the `OOF-IMP*` rule.
- [ ] Stale lock (sources edited after packing the lock) → refuse, reason `stale_lock`.
- [ ] Toolchain drift (manifest compiler/stdlib ≠ local) under `--match-toolchain` → refuse, reason `toolchain_drift`.
- [ ] Missing lock under `--require-lock` → refuse, reason `missing_lock`.
- [ ] Receipt is deterministic; the same artifact yields the same `artifact_digest`.
- [ ] No networking / registry / signing; full suite green; `git diff --check` clean.

## 5. Acceptance — mapping (this readiness)

- [x] Packet maps current package primitives to remote-node trust (§2).
- [x] States whether `.igpkg` source archive is enough for v0 (§3 Q2 — yes).
- [x] Defines required provenance fields (§3 Q4; +`lock_digest`/`entry_contract` gaps).
- [x] Defines node refusal conditions (§3 Q6).
- [x] Explains how `verify --strict` is used by a remote node (§2/§3 Q3 — `verify_archive` runs the engine offline).
- [x] Separates package trust from transport/auth/control-plane (§3 Q5).
- [x] Connects to network Kuramoto artifact lineage (§3 Q8).
- [x] Names first implementation proof + acceptance matrix (§4: `…-REMOTE-TRUST-P23`).
- [x] No code / no registry-semver claim / no remote-deploy changes; proof doc under `lab-docs/lang/`;
      `git diff --check` clean.

## 6. Closed scope (honored)

No registry, semver solver, remote network calls, deployment changes, or signatures (reserved as future
work). Execution authority stays out of `.ig`. Package trust stays content-addressed + local-first.

---

*Lab readiness packet. Verify-first: the `.igpkg` (P22, implemented) + `check_workspace_integrity` already let
a node verify a content-addressed source artifact offline; the home-lab archaeology already fixed remoteness
as a substrate/runtime/control-plane concern. v0 = source `.igpkg`, verified locally (digest + lock parity +
integrity + toolchain match), artifact digest in the receipt, refuse tampered/stale/drifted — transport/auth/
admission stay host + control-plane. First proof: `LAB-IGNITER-PACKAGE-REMOTE-TRUST-P23` (local node-admission,
no networking) with an 8-point matrix.*
