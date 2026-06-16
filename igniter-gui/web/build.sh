#!/usr/bin/env bash
# LAB-FRAME-GUI-ENGINE-REHOME-P8 — build the GUI browser bundle + serve it.
# The GUI runtime compiles to wasm32 over igniter-frame (machine-free); glue + a one-file page run
# the layout/hit-test/intent/reducer loop in the browser. Open http://127.0.0.1:8733/index.html
set -euo pipefail
cd "$(dirname "$0")/.."

# wasm-bindgen-cli must match the wasm-bindgen dep version (Cargo.lock):
#   cargo install wasm-bindgen-cli --version 0.2.125

rustup target add wasm32-unknown-unknown >/dev/null 2>&1 || true

cargo build --release --target wasm32-unknown-unknown --features wasm
wasm-bindgen --target web --no-typescript --out-dir web \
  target/wasm32-unknown-unknown/release/igniter_gui.wasm

echo "serving http://127.0.0.1:8733/index.html  (Ctrl-C to stop)"
exec python3 -m http.server 8733 --bind 127.0.0.1 --directory web
