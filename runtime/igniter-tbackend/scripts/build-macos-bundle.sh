#!/usr/bin/env bash
# Build a prebuilt macOS TBackend bundle (no Rust needed to *run* it).
# Run this ON macOS. Produces out/tbackend-<ver>-darwin-<arch>.tar.gz + sha + manifest.
#
# Usage:  ./scripts/build-macos-bundle.sh
#         VERSION=0.1.0-lab.1 ./scripts/build-macos-bundle.sh
set -euo pipefail
cd "$(dirname "$0")/.."

[ "$(uname -s)" = "Darwin" ] || { echo "run this on macOS (got $(uname -s))" >&2; exit 1; }
case "$(uname -m)" in
  arm64)  ARCH=arm64 ;;
  x86_64) ARCH=x86_64 ;;
  *) echo "unsupported macOS arch: $(uname -m)" >&2; exit 1 ;;
esac
VER_TAG="${VERSION:-0.1.0-lab.1}"
SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
NAME="tbackend-${VER_TAG}-darwin-${ARCH}"

echo "==> build release binary (darwin-${ARCH}) — pure Rust, no flags"
cargo build --release --bin tbackend
if cargo tree 2>/dev/null | grep -qiE 'magnus|rb-sys'; then
  echo "ERROR: magnus/rb-sys in the default tree — ffi feature leaked?" >&2; exit 1
fi

B="out/${NAME}"
rm -rf "$B"; mkdir -p "$B/bin" "$B/config" "$B/examples" "$B/scripts" "$B/var"
cp target/release/tbackend          "$B/bin/tbackend"
cp packaging/tbackend.dev.json      "$B/config/tbackend.dev.json"
cp examples/availability_ledger.py  "$B/examples/availability_ledger.py"
cp packaging/tbackend-dev           "$B/scripts/tbackend-dev"; chmod +x "$B/scripts/tbackend-dev"
cp packaging/README-quickstart.md   "$B/README-quickstart.md"

cat > "$B/manifest.json" <<EOF
{
  "name": "tbackend",
  "version": "${VER_TAG}+g${SHA}",
  "channel": "lab",
  "kind": "macos-bundle",
  "target": "darwin-${ARCH}",
  "git_commit": "${SHA}",
  "rustc": "$(rustc --version)",
  "built_at": "$(date -u +%Y-%m-%d)",
  "run": "./scripts/tbackend-dev {start|ping|stop}",
  "loopback_only": true,
  "auth_default": false
}
EOF

echo "==> tarball (AppleDouble/xattr-free)"
( cd out && COPYFILE_DISABLE=1 tar -czf "${NAME}.tar.gz" "${NAME}" )
( cd out && shasum -a 256 "${NAME}.tar.gz" | tee "${NAME}.tar.gz.sha256" )
echo "==> done: out/${NAME}.tar.gz"
ls -l "out/${NAME}.tar.gz"
