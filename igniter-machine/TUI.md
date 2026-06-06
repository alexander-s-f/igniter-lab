# Igniter Machine REPL Notes

The REPL is an optional lab-only terminal surface for the `igniter-machine`
prototype. It is useful for local experiments with contract loading, dispatch,
bitemporal facts, observations, and candidate `.igm` checkpoints.

It is not a public CLI, stable developer tool, release artifact, or runtime
support promise.

## Run Locally

```bash
cargo run --no-default-features --features repl --bin igniter-repl
```

Build a local release binary if you want a faster local loop:

```bash
cargo build --release --no-default-features --features repl --bin igniter-repl
./target/release/igniter-repl
```

Example backend flags:

```bash
./target/release/igniter-repl --backend rocksdb:./data
./target/release/igniter-repl --resume local-shadow.igm
./target/release/igniter-repl --backend remote_tcp:127.0.0.1:7401
```

## Command Sketch

```text
>> help          # list commands
>> contracts     # loaded contracts
>> load vendor_lead_pipeline.ig VendorLeadPipeline
>> dispatch VendorLeadPipeline {"lead_id":"l-42"}
>> write leads l-42 {"status":"active","amount":1500}
>> facts leads l-42
>> history leads l-42
>> checkpoint local-shadow.igm
>> observations
```

## Keyboard

| Key | Action |
| --- | --- |
| Up / Down | Command history |
| PgUp / PgDn | Scroll output |
| Tab | Contract-name autocomplete in `dispatch` |
| Ctrl+L | Clear screen |
| Ctrl+C / Esc | Exit |

## Boundary

- Lab-only REPL.
- Candidate `.igm` files are unstable local artifacts.
- No stable CLI, package, release, runtime, production, performance, or
  compatibility claims.
