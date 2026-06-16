#!/usr/bin/env bash
# LAB-FRAME-WASM-BROWSER-P6 — build the live browser bundle + serve it.
# Tooling step (kept separate from logic): compile the machine-free runtime to wasm32 and
# generate wasm-bindgen glue, then serve web/ over localhost. Open http://127.0.0.1:8731/index.html
set -euo pipefail
cd "$(dirname "$0")/.."

# wasm-bindgen-cli must match the wasm-bindgen dep version (see Cargo.lock):
#   cargo install wasm-bindgen-cli --version 0.2.125

rustup target add wasm32-unknown-unknown >/dev/null 2>&1 || true

# 1. compile the machine-free runtime to wasm32 (no kernel)
cargo build --release --target wasm32-unknown-unknown --no-default-features --features wasm

# 2. generate the ES-module glue (no bundler) into web/
wasm-bindgen --target web --no-typescript \
  --out-dir web \
  target/wasm32-unknown-unknown/release/igniter_frame.wasm

# 3. serve locally (ES modules + wasm require http, not file://)
echo "serving http://127.0.0.1:8731/index.html  (Ctrl-C to stop)"
exec python3 -m http.server 8731 --bind 127.0.0.1 --directory web
