# TBackend developer utilities

Legacy and local-development Ruby helpers live here. They are intentionally not
the preview install path.

Primary preview paths:

- macOS dev: prebuilt bundle (`packaging/README-quickstart.md`)
- devops/AWS: Docker (`docs/docker.md`)
- Linux ops: `.deb` package (`docs/deployment.md`)

Useful local commands from the package root:

```bash
ruby scripts/dev/tbackend_service.rb start
ruby scripts/dev/tbackend_repl.rb
ruby scripts/dev/tbackend_service.rb stop
```

The Rust daemon path is preferred for new work:

```bash
cargo build --release --bin tbackend
./target/release/tbackend --config tbackend.config.json
```
