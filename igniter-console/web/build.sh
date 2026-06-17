#!/usr/bin/env bash
# LAB-FRAME-APP-CONSOLE-P13 — build the console wasm bundle + serve it.
set -euo pipefail
cd "$(dirname "$0")/.."
rustup target add wasm32-unknown-unknown >/dev/null 2>&1 || true
cargo build --release --target wasm32-unknown-unknown --features wasm
wasm-bindgen --target web --no-typescript --out-dir web target/wasm32-unknown-unknown/release/igniter_console.wasm
echo "serving http://127.0.0.1:8735/console.html  (Ctrl-C to stop)"
exec python3 -m http.server 8735 --bind 127.0.0.1 --directory web
