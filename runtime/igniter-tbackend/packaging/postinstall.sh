#!/bin/sh
# tbackend postinstall — idempotent, conservative (no auto-start).
# Makes `apt install ./tbackend_*.deb` turn-key: creates the system user/group,
# owns the data/log dirs, reloads systemd. It deliberately does NOT enable or
# start the service — the operator does that explicitly (loopback service, but
# starting a daemon on install is a surprise we avoid).
set -e

if ! getent group tbackend >/dev/null 2>&1; then
    groupadd --system tbackend
fi
if ! getent passwd tbackend >/dev/null 2>&1; then
    useradd --system --no-create-home --shell /usr/sbin/nologin --gid tbackend tbackend
fi

# Own the runtime dirs (created by the package as empty dirs).
chown -R tbackend:tbackend /var/lib/tbackend /var/log/tbackend 2>/dev/null || true
chmod 0750 /var/lib/tbackend /var/log/tbackend 2>/dev/null || true

if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload || true
fi

cat <<'EOF'
tbackend installed (loopback 127.0.0.1:7401, auth disabled by default).
Next:
  sudo systemctl enable --now tbackend.service     # start + boot-persist
  systemctl is-active tbackend.service              # -> active
  ss -ltnp | grep 7401                              # -> 127.0.0.1:7401 only
To enable auth, see /usr/share/doc/tbackend/deployment.md (§ auth drop-in).
EOF
exit 0
