# TBackend — Install & Deploy

Two install tracks, with copy-pasteable recipes:

- **Track A — local dev**: build and run on your machine to try TBackend (the team "play with it" path).
- **Track B — devops / prod-like**: a packaged systemd service on a Debian/Ubuntu host (loopback-only,
  optional auth), with install / reinstall / update recipes.

Authority boundary (don't skip): TBackend's intended role is a **shadow side-ledger** — an existing system
stays the source of truth; TBackend records facts for audit/replay/point-in-time. See
`technical_architecture.md` §2 (Promotion Ladder) and `example-usecase.md`. The daemon is pure-Rust,
loopback-only by default, auth off by default.

Most of these recipes are **proven on real hardware** (`ai-main-lab` x86_64 Ubuntu 24.04; `pi5-lab2`
arm64 Debian 13). The proof history lives in `igniter-home-lab/cards/LAB-TBACKEND-{DISTRIBUTION-READINESS-P1,
PREBUILT-TARBALL-P3, DEB-PACKAGE-P4, DEB-INSTALL-SMOKE-P5, DEB-PERSISTENT-SERVICE-P6, AUTH-ENABLE-SERVICE-P6A,
AUTH-LIVE-UPGRADE-READINESS-P10, AUTH-LIVE-UPGRADE-P11}.md`. Where a recipe is **new / not yet device-proven**
it is marked ⚠.

---

## Track A — local dev

### Build (no flags — the daemon is pure Rust)

```bash
cargo build --release --bin tbackend     # -> target/release/tbackend
```

Do **not** pass `--no-default-features` (legacy) or `--features ffi` (that pulls in magnus/Ruby and builds
the optional FFI cdylib, not the daemon).

### Run

```bash
# durable (WAL on disk under ./data)
./target/release/tbackend --host 127.0.0.1 --port 7401 --data-dir data

# ephemeral (in-memory, perfect for a quick try / unit tests)
./target/release/tbackend --host 127.0.0.1 --port 7401 --data-dir nil
```

### Try it

```bash
ruby tbackend_repl.rb                     # time-traveling REPL (ping / put / list ...)
python3 examples/availability_ledger.py   # the worked example (see example-usecase.md)
```

Smoke from any client (length-prefixed CRC32 JSON over TCP): `{"op":"ping"}` → `{"ok":true,"pong":true}`.
That's the whole local-dev path — clone, build, run.

---

## Track B — devops / prod-like (packaged systemd service)

### B1. Build the binary (per arch, on a Linux node)

`cargo` **cannot** cross-compile to Linux from macOS, and there is no CI yet — build each arch natively on
a node of that arch:

```bash
# on the target host (x86 → amd64 deb, arm → arm64 deb)
. "$HOME/.cargo/env"                       # for non-interactive ssh
cargo build --release --bin tbackend
```

(Proven: amd64 on `ai-main-lab`, arm64 on `pi5-lab2`, rustc/cargo 1.96.0, source pinned `igniter-lab@<sha>`.)

### B2. Package — one-shot with nfpm  ⚠ new (supersedes the ad-hoc P4 assembly)

The earlier P4 `.deb` was hand-assembled on macOS via a Python `ar`/`tar` routine (because macOS `dpkg-deb`
embedded AppleDouble/xattr junk) — not repeatable, not checked in. This repo now ships a clean pipeline:

```bash
./scripts/build-and-package.sh            # build + nfpm -> out/tbackend_<ver>_<arch>.deb (+ .rpm) + SHA256SUMS
```

Spec: [`packaging/nfpm.yaml`](../packaging/nfpm.yaml) (payload, conffile, unit, maintainer scripts). nfpm
produces clean deb **and** rpm from one config, on any host (no `dpkg-dev`, no macOS `ar` hack). Payload:

```text
/usr/bin/tbackend
/etc/tbackend/tbackend.config.json        # active conffile (unit runs `tbackend --config`; edits survive upgrades)
/lib/systemd/system/tbackend.service      # loopback 127.0.0.1:7401, hardened
/var/lib/tbackend/  /var/log/tbackend/    # owned data + reserved log dirs (preserved on remove)
/usr/share/doc/tbackend/deployment.md
```

Verify a built `.deb` (proven recipe):

```bash
dpkg-deb -I out/tbackend_*.deb            # valid Debian 2.0, no xattr warnings
dpkg-deb -c out/tbackend_*.deb            # exact payload
tmp=$(mktemp -d); dpkg-deb -x out/tbackend_*.deb "$tmp"
file "$tmp/usr/bin/tbackend"              # ELF for the matching arch
systemd-analyze verify "$tmp/lib/systemd/system/tbackend.service"   # UNIT_VALID
```

> ✅ **Device-verified on arm64** (`pi5-lab2`, 2026-06-30): `./scripts/build-and-package.sh` built the
> release binary (44.95s) and nfpm produced a clean `tbackend_*_arm64.deb` **and** `.aarch64.rpm` in one
> run. Verified on the node: `dpkg-deb -I` valid Debian 2.0 with `postinst`+`postrm` present (turn-key),
> exact payload, `ExecStart=… --config …`, conffile shape, binary `ping→pong` smoke on a temp port — with
> the live `:7401` service untouched. **amd64** still needs a build on an x86 node (cargo not on
> `ai-main-lab` PATH today — see Forward plan). The legacy hand-built debs under
> `igniter-home-lab/artifacts/tbackend/p4/` are now superseded by this pipeline.

### B3. Install (turn-key)

With the nfpm package, `postinstall` creates the `tbackend` user/group and owns the dirs, so install is
self-contained:

```bash
sudo apt install ./out/tbackend_<ver>_<arch>.deb     # or: sudo dpkg -i ...
```

⚠ The **legacy P4 deb has no maintainer scripts** — for it you must do the user/ownership steps by hand
(proven on `pi5-lab2`):

```bash
sudo groupadd --system tbackend || true
sudo useradd --system --no-create-home --shell /usr/sbin/nologin --gid tbackend tbackend || true
sudo dpkg -i tbackend_<ver>_arm64.deb
sudo chown -R tbackend:tbackend /var/lib/tbackend /var/log/tbackend
sudo systemctl daemon-reload
```

### B4. Start the service

```bash
sudo systemctl enable --now tbackend.service     # start + boot-persist
systemctl is-active tbackend.service             # -> active
ss -ltnp | grep 7401                             # -> 127.0.0.1:7401 ONLY (peer 0.0.0.0:* is a false positive)
# {"op":"ping"} -> {"ok":true,"pong":true}
```

Unit ([`packaging/tbackend.service`](../packaging/tbackend.service)) runs
`/usr/bin/tbackend --config /etc/tbackend/tbackend.config.json`; the packaged config binds loopback only and
is a conffile, so operator edits survive upgrades. The service is hardened (`NoNewPrivileges`,
`ProtectSystem=full`, `ProtectHome`, `PrivateTmp`, `ReadWritePaths` scoped). Logs go to journald by default;
`/var/log/tbackend` is reserved for future/file-log use. Proven running on `pi5-lab2`. ⚠ Survival across an
actual **reboot** has not been tested.

### B5. Enable auth (optional) — edit the conffile

Because the unit runs `--config`, every runtime knob (`auth_enabled`, `durability`, `enable_compaction`,
`max_inflight_requests`, `hash_strict`, `commit_*`) is a one-line edit of the conffile
`/etc/tbackend/tbackend.config.json` (operator edits survive upgrades) + a restart:

```bash
sudo sed -i 's/"auth_enabled": false/"auth_enabled": true/' /etc/tbackend/tbackend.config.json
sudo systemctl restart tbackend.service
# journal: "Auth Enabled:true"
```

(The daemon reads `auth_enabled` from `--config` — `src/main.rs`. A systemd drop-in that overrides
`ExecStart` with extra CLI flags still works as an alternative, but the conffile is the clean path now.)

Roles: `admin` / `read_only` / `write_only` / `peer`; store ACL via `allowed_stores`. On first auth boot the
server mints a one-time `BOOTSTRAP_ADMIN_TOKEN` (mode 0600) under `<data_dir>/security/`; use it to create
your real tokens (`auth_token_create`), then delete the handoff file. See `user_guide.md` §2.G–I.

> ⚠ **Security note on package version.** The device-proven P4 binary is **pre-P9**: persistent token
> *filenames are the token value* (`security/<TOKEN>.json`), so `ls security/` leaks tokens. The **P9**
> hardening (hash/id storage `security/<blake3(token)>.json`, fail-closed on legacy files) is in source and
> tested (`verify_auth.rb` 67/0) but **was never packaged/installed** (the P11 upgrade is HELD — see B6).
> Package from current source (B2) to get P9; do not enable auth on a pre-P9 binary you care about.

### B6. Reinstall / update

**Plain reinstall (same or newer version, data preserved):**

```bash
sudo systemctl stop tbackend.service
sudo apt install ./out/tbackend_<newver>_<arch>.deb     # conffile preserved; /var/lib/tbackend untouched
sudo systemctl start tbackend.service
```

`dpkg -r` keeps `/var/lib/tbackend` (the ledger); only `dpkg --purge` removes data (postremove guards this).

**Live auth-storage upgrade (pre-P9 → P9): ⚠ documented but NOT yet runnable.** The safe sequence (from
P10/P11) is: build a **P9-capable** deb (B2) → back up the current binary + unit + `tar -czf` the
`security/` dir (mode 600) into a root-only 0700 dir → `stop` → `dpkg -i` → `daemon-reload` → `start` →
capture the new `BOOTSTRAP_ADMIN_TOKEN` *without `cat`* → mint replacement tokens → retire legacy plaintext
files → remove the bootstrap handoff. Rollback at each step = restore the saved binary + `security` tar.

**This path is HELD.** P11 stopped before any mutation because the operator gate was unmet
(`operator_approval / maintenance_window / secret_store_ready / rollback_owner` all missing) **and no
P9-capable arm64 deb was ever produced**. So "update a running auth-enabled service" is a runbook on paper +
source-proven, not an executed recipe. Closing it needs: (1) the nfpm pipeline run on the arm node to
produce a P9 deb, (2) the human operator gate.

---

## Recipe cheat-sheet

| goal | command |
|------|---------|
| dev: build + run | `cargo build --release --bin tbackend && ./target/release/tbackend --host 127.0.0.1 --port 7401 --data-dir data` |
| dev: try | `python3 examples/availability_ledger.py` · `ruby tbackend_repl.rb` |
| package | `./scripts/build-and-package.sh` (on a Linux node of the target arch) |
| install (nfpm deb) | `sudo apt install ./out/tbackend_<ver>_<arch>.deb` |
| start | `sudo systemctl enable --now tbackend.service` |
| status | `systemctl is-active tbackend.service` · `ss -ltnp \| grep 7401` |
| enable auth | edit conffile `"auth_enabled": true` + `sudo systemctl restart tbackend.service` (B5) |
| reinstall | `stop` → `apt install ./out/...deb` → `start` |
| remove (keep data) | `sudo dpkg -r tbackend` |
| purge (delete data) | `sudo dpkg --purge tbackend` |

---

## Device targets (home lab)

| | `pi5-lab2` | `ai-main-lab` |
|---|---|---|
| arch / OS | arm64 / Debian 13 | x86_64 / Ubuntu 24.04 |
| role | runs the persistent packaged `tbackend.service` (loopback :7401) | runs the original native P1 service (loopback :7401) |
| ssh | `ssh pi5-lab2` | `ssh ai-main-lab` |

**Secrets rule:** sudo/ssh passwords live only in `igniter-home-lab/.env` (`HOMELAB_*`), git-ignored —
**never print them**; feed to `sudo -S` via stdin. Device facts: `igniter-home-lab/docs/inventory/`.
**Both nodes already run a pre-P9 `:7401` service** — never disrupt it; verify new builds on an **unused
port + temp data dir**.

---

## Status & forward plan

**Proven (device-verified):** native per-arch build · cross-arch tarball (P3) · `.deb` shape + verify (P4) ·
install + smoke + data-preservation (P5) · persistent systemd service, loopback, hardened (P6) · auth-enable
drop-in (P6A).

**Now device-proven (arm64):** the nfpm one-shot pipeline (`scripts/build-and-package.sh` + `packaging/`) —
clean deb **+ rpm** with maintainer scripts → **turn-key install** (closes the "no build/package script" and
"manual user/chown" gaps). Verified on `pi5-lab2` 2026-06-30: build 45 s, deb+rpm produced, `postinst`/`postrm`
present, `--config` unit, `ping→pong` smoke on a temp port, live `:7401` untouched.

**Open gaps → forward order:**
1. **amd64 deb + full turn-key `apt install`.** The arm64 deb is device-proven; still to do: build the amd64
   deb on an x86 node (install rustup on `ai-main-lab` — cargo not on PATH today), and run a real
   `apt install + systemctl enable` on a node/port that does **not** collide with the live `:7401` (a free
   node or a maintenance window). ← next.
2. **CI / cross-build** so artifacts don't require an SSH round-trip per arch (qemu or GitHub Actions).
3. **Signed apt repo** → `apt install tbackend` + upgrade-via-apt (today install is `dpkg -i` of a file).
4. **Execute the live auth-upgrade** (B6) once a P9 deb exists + the operator gate is granted.
5. **Reboot/boot-survival test** (the never-run P7).
6. **Docker image** lane (parallel, optional).
7. Auth transport hardening (TLS/mTLS/unix-socket; today bearer-in-JSON over loopback).
