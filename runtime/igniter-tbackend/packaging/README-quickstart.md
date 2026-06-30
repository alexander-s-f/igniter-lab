# TBackend — macOS quickstart (no Rust needed)

A prebuilt, loopback-only TBackend daemon you can run in 30 seconds to understand it. No Rust, no systemd,
no Docker, no root, no network exposure. Everything stays under this folder.

## Run it

```bash
./scripts/tbackend-dev start          # start the daemon on 127.0.0.1:7401 (data -> ./var/data)
./scripts/tbackend-dev ping           # -> {"ok":true,"pong":true}
python3 examples/availability_ledger.py   # the worked example (idempotent append, time-travel, audit)
./scripts/tbackend-dev stop           # stop it (nothing keeps running)
```

That's the whole loop: **start → ping → example → stop.**

## What you're looking at

TBackend is a **bitemporal append-only ledger**: every change is a fact, and you can ask "what did we know
at time T?" and "why?". The example walks an availability ledger (idempotent durable write, point-in-time
read, clock-free audit order, lineage). See the comments in `examples/availability_ledger.py`.

## Notes

- **Loopback only** (`127.0.0.1:7401`), **auth off** — this is a local dev bundle, not a server install.
- Data is durable under `./var/data` (delete it to reset). Edit `config/tbackend.dev.json` to change the
  port / data dir / `auth_enabled` / `durability`.
- This is a **lab** artifact — not a production/release surface. For the full story (architecture, the two
  install tracks, deployment), see the source repo's `docs/` (`technical_architecture.md`, `user_guide.md`,
  `example-usecase.md`, `deployment.md`).

`manifest.json` records the exact version, git commit, and rustc this bundle was built from.
