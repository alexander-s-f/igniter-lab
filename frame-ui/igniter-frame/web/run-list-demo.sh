#!/usr/bin/env bash
# LAB-FRAME-LAYOUT-VOCAB-P2 — build + serve the composable list/detail demo.
# One command: compile the machine-free runtime to wasm32, generate wasm-bindgen glue, serve web/.
# Open  http://127.0.0.1:8736/list.html
set -euo pipefail
cd "$(dirname "$0")/.."

# wasm-bindgen-cli must match the wasm-bindgen dep version (Cargo.lock):  cargo install wasm-bindgen-cli --version 0.2.125
rustup target add wasm32-unknown-unknown >/dev/null 2>&1 || true

# 1. compile the machine-free runtime to wasm32 (no kernel)
cargo build --release --target wasm32-unknown-unknown --no-default-features --features wasm

# 2. generate the ES-module glue (no bundler) into web/
wasm-bindgen --target web --no-typescript \
  --out-dir web \
  target/wasm32-unknown-unknown/release/igniter_frame.wasm

# 3. serve locally (ES modules + wasm require http, not file://)
echo "serving  http://127.0.0.1:8736/list.html   (Ctrl-C to stop)"
exec python3 -m http.server 8736 --bind 127.0.0.1 --directory web
