# lab-distribution-repl-fleet-inclusion-readiness-p17-v0 — what is `igniter-repl` in distribution?

Card: `LAB-DISTRIBUTION-REPL-FLEET-INCLUSION-READINESS-P17`
Status: CLOSED (2026-06-25)
Authority: lab readiness — a recommendation, not a promotion. Closed surfaces honored: no installer/wrapper
change, no REPL/TUI work, no new default dependency, no fleet promotion without a follow-up impl card.

## Verify-first evidence (live, 2026-06-25)

| Check | Result |
|---|---|
| `cargo build --release --bin igniter-repl --features repl` | **Finished** (recovered by `LAB-MACHINE-REPL-ASYNC-RESUME-FIX-P1`; binary 4.6M) |
| startup smoke `igniter-repl --resume /nonexistent.igm` | exit 1, "Failed to resume machine: IO error…" — drives the fixed `block_on(resume)` **before** the TUI; proves link/run only |
| `cargo tree -e normal --no-default-features` | **0** `ratatui`/`crossterm` (excluded) |
| `cargo tree -e normal --no-default-features --features repl` | `ratatui 0.26` + `crossterm 0.27` present |
| `runtime/igniter-machine/Cargo.toml` | `default = []`; `repl = ["dep:ratatui", "dep:crossterm"]`; the `[[bin]] igniter-repl` has `required-features = ["repl"]` (hard-gated) |
| `bin/igniter-install` `FLEET` | 5 binaries (igc, igniter-vm, igweb-serve, igniter-mcp, tbackend) — **repl not built** |
| `bin/igniter` toolchain/doctor | relabeled to "excluded from v0 fleet (release build recovered; inclusion pending)"; still uses the `[blocked]` *state label* on one line |

**Key fact (decides the dependency question):** `ratatui`/`crossterm` appear ONLY under `--features repl`.
`default = []` stays clean, and the binary is `required-features = ["repl"]`, so it cannot even build into a
default invocation. Opt-in REPL therefore changes **no** default dependency boundary.

**Testability fact:** `igniter-repl` is an interactive ratatui TUI — raw mode + alternate screen, a 200 ms
event loop, no `--help`, no non-interactive/headless mode. The only hermetic smoke today is the **pre-TUI**
`--resume /nonexistent` linkage check; the REPL's own commands (load/dispatch/checkpoint/resume) have **no
non-interactive exercise**. The 5 fleet tools each have a hermetic functional smoke (e.g. `igweb-serve` →
HTTP 200, `igc package graph` → JSON); `igniter-repl` does not.

## Questions answered

1. **What is it?** A **developer-only diagnostic** — a Smalltalk-style live machine workspace TUI. Not a
   user-facing shipped tool (no scripting surface, interactive-only), not throwaway-experimental (it builds
   and is useful for poking a machine).
2. **Minimum smoke for inclusion?** A **non-interactive exercise of REPL command dispatch** — a headless/
   scripted-input path that loads a contract, dispatches it, checkpoints, resumes, and exits non-zero on
   failure. The current `--resume /nonexistent` proves only that the binary links and the fixed async path
   runs; it does **not** prove the REPL functions. Fleet inclusion needs the former.
3. **Should `igniter-install` build it?** **Under a flag, opt-in; never by default in v0.** Default install
   stays the 5 hermetically-smokeable tools; `--with-repl` (future) would add it for users who want it.
4. **`toolchain list` state?** Show it as **`[optional]`** (builds under `--features repl`; not in the
   default fleet), replacing the `[blocked]` label which now mis-reads as "broken". Exact wording in
   "Exclusion wording" below.
5. **Dependency boundary?** **No change.** `ratatui`/`crossterm` are opt-in-only (proven by `cargo tree`);
   `default = []` is unaffected; the binary is `required-features`-gated.
6. **Follow-up card?** `LAB-DISTRIBUTION-REPL-HEADLESS-SMOKE-P*` (gate), then conditionally
   `LAB-DISTRIBUTION-REPL-INSTALLER-OPTIN-P*` (promotion). Named in "Follow-ups".

## Alternatives compared

| # | Option | Verdict |
|---|---|---|
| **A** | Include `igniter-repl` in the v0 toolchain fleet (installer builds it, `toolchain list` `[present]`) | **Reject for v0.** Ships a tool the install cannot functionally verify (interactive TUI, no hermetic smoke), and adds the `ratatui`/`crossterm` build to every install. Build-green ≠ ship-ready. |
| **B** | **Keep buildable but opt-in / excluded from the default fleet** | **★ Recommended.** Matches live reality and the proven dependency isolation. Zero risk: default install unchanged, no new default dep. Relabel the *state* (not "blocked") and gate promotion on a real smoke. |
| **C** | Split into a separate `dev-tools` profile | **Defer.** Premature taxonomy for a single dev TUI; revisit when there is ≥2 dev-only binaries. Folds naturally out of B later. |
| **D** | Defer distribution until a non-interactive REPL smoke exists | **Adopt as the promotion gate, not the current state.** B *is* the current state; D's bar (a headless smoke) is exactly what must pass before A. So: B now, with D as the explicit gate to A. |

## Recommendation — **B now, with the D gate to A**

Keep `igniter-repl` **buildable under `--features repl`, excluded from the default v0 fleet and the default
installer**. This is the honest live status and is dependency-safe. **Promotion to A (fleet inclusion)** is
gated on TWO things, each its own follow-up card:

1. a **non-interactive REPL smoke** (load → dispatch → checkpoint → resume, headless, exit-coded) — so the
   tool is verifiable the way the other 5 are; AND
2. an **installer opt-in** (`igniter-install --with-repl`) + a `toolchain list` `[optional]→[present]`
   transition when built.

Until both land, repl stays opt-in. Build-recovery alone does **not** justify promotion.

### If exclusion (B) stands — exact wording for `doctor` / `toolchain list`

Replace the residual `[blocked]` *state* (which reads as "broken") with `[optional]`, keeping the recovered-
build truth:

- `toolchain list` / `toolchain_report`:
  `[optional] igniter-repl — builds with --features repl; not in the default v0 fleet (inclusion: P17 → headless-smoke gate)`
- `doctor` (`doc_emit toolchain igniter-repl info …`):
  `optional (release build recovered; opt-in via --features repl; not in default fleet — P17)`
- `toolchain list` header: `v0 fleet (5 default binaries; igniter-repl optional, opt-in)`

(These are wording-only and belong to a docs-hygiene follow-up, not this readiness card — no wrapper change
is made here.)

## Docs-hygiene vs distribution policy (separated)

- **Policy (correct, unchanged):** the default fleet is 5 binaries; repl is opt-in. `bin/igniter-install`
  `FLEET` correctly omits repl. **No policy change is recommended for v0.**
- **Docs-hygiene gap (stale, NOT policy):** `bin/igniter-install` still says repl is **"build-broken (P3)"**
  in 4 places (header comment, usage, the install-manifest `excluded.reason`, and the final summary), and
  `bin/igniter` still carries one `[blocked]` *state label*. The build is recovered, so "build-broken" is
  false. This is a wording fix only; it does **not** change what gets built. Route it to a narrow
  docs-hygiene card (below) — it must update the `igniter-install` manifest `reason` string and the wrapper
  label together with the `igniter_toolchain_list_names_fleet_and_marks_repl` test assertion (currently
  asserts `[blocked]`).

## Follow-ups

1. **`LAB-DISTRIBUTION-REPL-LABEL-HYGIENE-P*`** (docs-hygiene) — replace "build-broken (P3)" / `[blocked]`
   with the `[optional]` wording above across `bin/igniter` + `bin/igniter-install` (incl. the manifest
   `excluded.reason`), and update the wrapper test assertion from `[blocked]` to `[optional]`. No fleet/policy
   change. *Smallest, do first.*
2. **`LAB-DISTRIBUTION-REPL-HEADLESS-SMOKE-P*`** (impl, the A-gate) — add a non-interactive REPL path
   (scripted-input/headless mode) and a hermetic test exercising load/dispatch/checkpoint/resume.
3. **`LAB-DISTRIBUTION-REPL-INSTALLER-OPTIN-P*`** (impl, conditional on #2) — `igniter-install --with-repl`
   and the `[optional]→[present]` transition. Only after #2 proves functional smoke.

## Acceptance trace

- [x] Packet cites live build/tree/smoke evidence (table above; re-run 2026-06-25).
- [x] ≥4 alternatives compared (A/B/C/D).
- [x] One recommendation selected with a clear gate (B now; D as the explicit gate to A; two-card promotion).
- [x] Inclusion path's required installer/wrapper/test changes specified (follow-ups #2/#3).
- [x] Exclusion wording for `doctor` / `toolchain list` specified (`[optional]` strings above).
- [x] Stale-doc cleanup separated from distribution policy (the `build-broken` text is hygiene, not policy).
- [x] No code changes (readiness packet only).
