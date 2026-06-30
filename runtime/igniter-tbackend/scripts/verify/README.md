# TBackend verification scripts

Focused lab proofs live here so the package root stays readable.

Run from the package root:

```bash
cargo build --release --bin tbackend
ruby scripts/verify/verify_auth.rb
python3 scripts/verify/verify_seqid.py
```

Useful groups:

```bash
make test          # Rust unit tests
make verify-auth   # auth/storage/bootstrap proof
make verify-core   # compact Rust + auth proof
```

Most scripts start a temporary loopback daemon, write ignored `*_data` and
`*_daemon.log` paths, then clean up after themselves. They are proof harnesses,
not public product commands.
