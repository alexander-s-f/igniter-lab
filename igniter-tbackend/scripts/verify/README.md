# TBackend verification scripts

Focused verification checks live here so the package root stays readable.

Run from the package root:

```bash
cargo build --release --bin tbackend
ruby scripts/verify/verify_auth.rb
python3 scripts/verify/verify_seqid.py
```

Useful groups:

```bash
make test          # Rust unit tests
make verify-auth   # auth/storage/bootstrap check
make verify-core   # compact Rust + auth check
```

Most scripts start a temporary loopback daemon, write ignored `*_data` and
`*_daemon.log` paths, then clean up after themselves. They are maintainer checks,
not the team quickstart path.
