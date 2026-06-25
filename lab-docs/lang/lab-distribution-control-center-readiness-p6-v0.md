# lab-distribution-control-center-readiness-p6-v0 — `igniter` as the long-lived control center

> **Partly superseded (2026-06-25):** `igniter app bundle` is no longer "RESERVED/deferred" — it is
> **implemented (P14)** and run-proven (P16); `package`/`toolchain install|update` are **live** (P12/P11).
> For the live surface see [`lab-distribution-implemented-surface-v0.md`](lab-distribution-implemented-surface-v0.md).
> The rest of this taxonomy packet stands as history.

**Card:** `LAB-DISTRIBUTION-CONTROL-CENTER-READINESS-P6` · **Type:** readiness (taxonomy decision, **no code**).
**Authority: lab readiness — a recommendation, not an implementation.** Closed surfaces honored: no
implementation, no install script, no root workspace, no binary rename, no public release/upload/registry/
signing/Homebrew/Docker.

## Bottom line

Make **`igniter` the single durable front door**, a **shell dispatcher in v0** (extend the P2 `bin/igniter`),
that **delegates** to the existing owners and never reimplements them. The v0 taxonomy is:

```text
igniter serve <app>          → igweb-serve            (DONE in P2)
igniter check <app>          → igweb-serve check      (app dry build, no socket)
igniter compile <srcs|root>  → igc compile            (delegate to the compiler)
igniter run <igapp> …        → igniter-vm run         (delegate to the VM)
igniter package {lock|verify|graph|pack|admit}  → igc {lock|verify|package …}   (1:1 delegation, no 2nd resolver)
igniter toolchain {list|install|update}         → bootstrap build/stage of the local fleet (v0: local only)
igniter doctor               → NEW minimal env check (rustc? igniter-lang sibling? binaries on PATH?)
igniter app bundle           → RESERVED, deferred (stays in home-lab release-bundle/systemd scripts for now)
```

`igniter-install` is **bootstrap-only**: it builds/stages the first real `igniter` + fleet, prints next
steps, and leaves the daily workflow. Ongoing updates are `igniter toolchain update`, not the installer.

## Verify-first basis (P1–P5 + live command owners)

- Read `bin/igniter` (P2 wrapper — verb `serve` only today). Read P1–P5 packets.
- **Command owners (confirmed in source):**
  | Owner binary | Verbs (live) | Source |
  |---|---|---|
  | `igweb-serve` | `[run]`, `check`; `--addr`(loopback-only)/`--max-requests`/`--host-config` | `server/igniter-web/src/bin/igweb-serve.rs` + `lib.rs` |
  | `igc` (`igniter_compiler`) | `compile`, `lock`, `verify`, `package {graph,pack,verify,admit}` | `lang/igniter-compiler/src/main.rs:21-58,300-469` |
  | `igniter-vm` | `run`, `compile`, `trace`, `bytecode-map` | `lang/igniter-vm/src/main.rs:37-354` |
  | `igniter-mcp` | stdio MCP server (no verbs) | `runtime/igniter-machine/src/bin/mcp.rs` |
  | `tbackend` | daemon (FFI-free default) | `runtime/igniter-tbackend` |
- **No root workspace** (confirmed; P5 keeps package-local). **No binary literally named `igniter`** exists →
  the front-door name is free (no collision).
- **`igniter-repl` is build-broken** (P3, async E0308) → not part of the v0 control center.
- **Name caveat:** the compiler artifact is `igniter_compiler`, not `igc` (P1/P3) — the dispatcher resolves
  the real artifact and the bootstrap installs it as `igc` (no rename in *this* card — closed surface).

## The 8 required answers

**1. Command families under `igniter` v0.** App lifecycle (`serve`, `check`), language tools (`compile`,
`run`), packaging (`package …`), toolchain (`toolchain {list|install|update}`), diagnostics (`doctor`), and
the **reserved** deployment family (`app bundle`, deferred). Acceptance set `serve/check/doctor/toolchain/
package/app` all named.

**2. Public vs implementation-detail binaries.** `igniter` is **the** public front door. The owners stay the
real implementations and remain directly invocable (no hiding, no rename — closed surface), but the
*recommended* surface routes through `igniter`:
- `igweb-serve` → behind `igniter serve`/`igniter check` (implementation detail for daily DX).
- `igniter_compiler`/`igc` → behind `igniter compile`/`igniter package …` (igc stays the package authority).
- `igniter-vm` → behind `igniter run` (still the canonical runner; `trace`/`bytecode-map` stay VM-direct, dev-only).
- `igniter-mcp` → **stays a distinct public surface** (agent/MCP host invokes it; not a daily dev verb). A
  future `igniter mcp` alias is optional, deferred.
- `tbackend` → **stays standalone** (ops daemon, its own tarball/`.deb` lane) — **not** under daily `igniter` DX.

**3. Shell, Rust, or staged?** **Staged: shell dispatcher in v0**, Rust CLI later. v0 extends P2's
`bin/igniter` (zero infra, no workspace per P5, no new crate). Promote to a Rust `igniter` crate when
`doctor`/`toolchain`/`package` need structured logic, machine-readable output, and richer UX — *after* the
taxonomy is proven. Keep P2's discipline: **no shell-hidden semantics** (forward argv + one env var), so the
shell→Rust transition is a drop-in and a release bundle/systemd unit can call the same verbs unchanged.

**4. `igniter-install` bootstrap-only role.** It is the *one-time* entry: build the 5 green binaries, stage to
a PATH prefix, install `igniter` itself + `igniter_compiler` as `igc`, run a loopback smoke, print "use
`igniter …` from here". It is **not** a long-lived package manager and owns **no** daily verb — once `igniter`
exists, the installer exits the user's workflow; updates flow through `igniter toolchain update`.

**5. `igniter package …` delegation.** **1:1 forwarding to `igc`, no second package manager.** `igniter
package lock` → `igc lock`; `igniter package verify` → `igc verify` (workspace drift+integrity); `igniter
package {graph,pack,admit}` → `igc package {graph,pack,admit}`; `igniter package verify <file.igpkg>` → `igc
package verify` (the file form). The compiler remains the sole owner of the resolver, `igniter.lock`,
content-hashing, and `STDLIB_VERSION`. `igniter` adds **only** an alias surface — it must never invent a lock
format, resolver, or registry.

**6. `igniter toolchain …` meaning.** **v0 = local only.** `toolchain list` = show installed `igniter`
binaries + version/sha/feature-set (from the bootstrap manifest); `toolchain install`/`update` = re-run the
local build+stage from the source tree (no remote download). **Later (deferred):** remote channels/versions,
download, pinning to a published toolchain, signature verification — that is the registry/package-pull future,
out of v0.

**7. `igniter app bundle` ownership.** **Reserved name, deferred implementation.** For now the **home-lab
release-bundle + systemd scripts stay the owner** (Model E, proven on pi5: `deploy/pi5-lab/*` +
`igniter-stack-deployment-models.md`). When implemented, `igniter app bundle` should own **assembling** the
versioned unit `{runner binary + app dir + checks + manifest}` only — it must **not** own systemd install,
bind/exposure policy, or secrets (host-owned per the deployment-models app/host split). Rollback
(versioned-dir + `current` symlink) and the unit stay host/script concerns in v0.

**8. Explicitly deferred (≥5 non-goals).**
1. `igniter app bundle` implementation (scripts own it in v0).
2. `igniter toolchain` remote/registry/download/signing.
3. `igniter` as a Rust CLI (shell-first; Rust is the staged follow-on).
4. `igniter mcp` / `igniter daemon` (igniter-mcp + tbackend stay standalone).
5. `igniter publish`/`login`/`registry` (no package upload — closed surface).
6. `igniter update` self-update; `igniter new`/scaffolding; Docker/Homebrew subcommands.
7. Anything touching `igniter-repl` (build-broken).
8. Binary rename of `igniter_compiler` → `igc` (handled at install time, not as a control-center change).

## Authority boundaries (the durable invariant)

`igniter` is a **routing/ergonomics layer with no authority of its own** — exactly the P2 principle extended:
- **Loopback/public-bind, request bound** → owned by `igweb-serve` (refuses non-loopback `--addr`); `igniter`
  forwards, never relaxes.
- **Secrets / host authority** → `--host-config` templates, env-only DSNs; `igniter` passes through, bakes
  nothing.
- **Package trust** (lock/verify/content-hash/STDLIB_VERSION) → owned by `igc`; `igniter` aliases only.
- **Effect/machine capability** → owned by `igniter-machine` (opt-in `machine` feature); `igniter` does not
  gate or grant it.
A command may be added to `igniter` only if a **named owner** already enforces its authority — no verb
invents new authority.

## Collision check

`serve` (new), `check` (igweb-serve `check`), `compile` (→ igc; note igniter-vm also has `compile` — `igniter
compile` binds to **igc**, the compiler), `run` (→ igniter-vm), `package …` (→ igc), `doctor`/`toolchain`/`app`
(new namespaces, no existing binary or verb collides). No binary named `igniter` exists, and the downstream
distribution cards are already cleanly numbered (P7/P8/P9 — no suffix collision).

## Next implementation cards (already drafted — sequence, don't invent)

The downstream distribution wave is already drafted; this packet **feeds** these existing cards rather than
naming new ones:

1. **`LAB-DISTRIBUTION-CONTROL-CENTER-CLI-SKELETON-P7`** (exists, OPEN — **unblocked by closing this P6**) —
   turn the taxonomy into the minimal `bin/igniter` skeleton: `serve` (P2-compatible), `check`, `doctor`,
   `toolchain list`, `package --help`, `app --help` — honest delegation + fail-closed placeholders, no new
   authority. **P6 feeds it:** the Bottom-line taxonomy + the authority invariant + the delegation table.
2. **`LAB-DISTRIBUTION-BOOTSTRAP-INSTALL-P8`** (exists, OPEN) — the P4-recommended bootstrap installer (build
   the 5 green binaries → stage → `igniter`/`igc` on PATH → verify `igniter-lang` sibling → loopback smoke).
   Bootstrap-only per Q4.
3. **`LAB-DISTRIBUTION-DOCTOR-READINESS-P9`** (exists, OPEN) — designs `igniter doctor`'s checks/output;
   **P6 reserves the `doctor` verb and defers its detailed design to P9** (non-mutating, inspect/explain/suggest).
4. *(genuinely-new, not yet drafted)* a **`LAB-MACHINE-REPL-ASYNC-RESUME-FIX`** card (`.await`
   `checkpoint`/`resume` so `igniter-repl` builds) and, later, an `igniter` **Rust-CLI** promotion card once
   the taxonomy + `doctor`/`toolchain` UX justify leaving the shell dispatcher.

## Acceptance — mapping

- [x] Stable taxonomy named, incl. `serve`, `check`, `doctor`, `toolchain`, `package`, `app` (Bottom line).
- [x] `igniter-install` stated **bootstrap-only**, not a long-lived package manager (Q4).
- [x] Existing command owners mapped + delegation boundaries clear (verify-first table + Q1/Q2/Q5).
- [x] Public vs internal story for `igweb-serve`, `igniter_compiler`/`igc`, `igniter-vm`, `igniter-mcp`, `tbackend` (Q2).
- [x] ≥5 deferred commands/non-goals (Q8 lists 8).
- [x] Next implementation cards named — existing P7 (CLI skeleton), P8 (bootstrap), P9 (doctor readiness); + new repl-fix / later Rust-CLI.
- [x] No code changes; `git diff --check` clean.

## Closed surfaces (honored)

No implementation, no install script, no root workspace, no binary rename, no public release, no upload/
registry/signing/Homebrew/Docker/production service install.

---

*Lab readiness. 2026-06-24. `igniter` = the single durable front door, a v0 **shell dispatcher** that
**delegates** (serve→igweb-serve, compile→igc, run→igniter-vm, package→igc lock/verify/package, toolchain=local
build/stage, doctor=env check) and owns **no authority** — every verb routes to a named owner that enforces
loopback/secret/package trust. `igniter-install` is bootstrap-only; `app bundle` stays in release-bundle/
systemd scripts. Staged shell→Rust transition. Feeds the already-drafted
P7 (CLI skeleton), P8 (bootstrap installer), P9 (doctor readiness).*
