#!/usr/bin/env bash
# One-shot: build the tbackend release binary + produce a clean .deb (and .rpm)
# with nfpm and maintainer scripts.
#
# Run this ON a Linux target of the desired arch. cargo cannot cross-compile to
# Linux from macOS, so build amd64 on an x86 node and arm64 on an arm node
# (e.g. ai-main-lab / pi5-lab2). nfpm itself is cross-platform; only the binary
# build is arch-bound.
#
# Usage:  ./scripts/build-and-package.sh         (version derived from git sha)
#         VERSION=0.1.0-abc1234 ./scripts/build-and-package.sh
set -euo pipefail
cd "$(dirname "$0")/.."

PKG_VER="${VERSION:-0.1.0-$(git rev-parse --short HEAD 2>/dev/null || echo dev)}"
case "$(uname -m)" in
  x86_64|amd64)   ARCH=amd64 ;;
  aarch64|arm64)  ARCH=arm64 ;;
  *) echo "unsupported arch: $(uname -m)" >&2; exit 1 ;;
esac
export VERSION="$PKG_VER" ARCH

echo "==> build release binary  (arch=$ARCH version=$PKG_VER) — pure Rust, no flags"
cargo build --release --bin tbackend

echo "==> sanity: daemon dependency tree must be FFI/Ruby-free"
if cargo tree 2>/dev/null | grep -qiE 'magnus|rb-sys'; then
  echo "ERROR: magnus/rb-sys in the default tree — did someone re-enable the ffi feature?" >&2
  exit 1
fi

mkdir -p out
if ! command -v nfpm >/dev/null 2>&1; then
  echo "nfpm not found. Install: https://nfpm.goreleaser.com (single Go binary)." >&2
  echo "Binary is built at target/release/tbackend; package step skipped." >&2
  exit 2
fi

echo "==> package .deb"
nfpm pkg --packager deb --config packaging/nfpm.yaml --target "out/tbackend_${PKG_VER}_${ARCH}.deb"
echo "==> package .rpm (best-effort)"
nfpm pkg --packager rpm --config packaging/nfpm.yaml --target out/ 2>/dev/null || echo "  (rpm skipped — ok)"

( cd out && sha256sum tbackend_* > SHA256SUMS )
echo "==> done"
ls -la out/
echo
echo "Install (turn-key — postinstall creates the user + owns dirs):"
echo "  sudo apt install ./out/tbackend_${PKG_VER}_${ARCH}.deb"
echo "  sudo systemctl enable --now tbackend.service"
