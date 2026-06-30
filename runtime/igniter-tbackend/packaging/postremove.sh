#!/bin/sh
# tbackend postremove — NEVER deletes data on a plain remove.
# `apt remove` / `dpkg -r`  : keep /var/lib/tbackend (the ledger) and the user.
# `apt purge`  / `dpkg -P`  : the package purges conffiles; we additionally remove
#                             the data/log dirs and the system user ONLY on purge.
set -e

case "$1" in
    purge)
        rm -rf /var/lib/tbackend /var/log/tbackend 2>/dev/null || true
        if getent passwd tbackend >/dev/null 2>&1; then userdel tbackend 2>/dev/null || true; fi
        if getent group tbackend  >/dev/null 2>&1; then groupdel tbackend 2>/dev/null || true; fi
        ;;
    remove|upgrade|deconfigure|*)
        # keep data + user; allow clean upgrades to reuse them
        ;;
esac

if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload || true
fi
exit 0
