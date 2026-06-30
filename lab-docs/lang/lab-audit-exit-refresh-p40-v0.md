# LAB-AUDIT-CONTROL-BOARD-EXIT-REFRESH-P40 v0

Date: 2026-06-28
Status: DONE
Route: standard / main-audit / control-board / exit-readiness
Card: `.agents/work/cards/lang/LAB-AUDIT-CONTROL-BOARD-EXIT-REFRESH-P40.md`
Depends-On: `LAB-IGNITER-WEB-LIVE-BIND-HUMAN-GATED-PROOF-P39`

## Result

The foundation-audit digestion wave can exit the active audit lane.

This does **not** mean "Igniter is production-hosting ready". It means the audit
items that were blocking continued product/science/DX work now have one of three
clear states:

- closed by implementation/proof;
- closed for a bounded lab surface with production explicitly deferred;
- intentionally owned by another lane and no longer blocking the audit wave.

Historical audit packets remain evidence snapshots. Current truth is the live
source plus package-local implemented-surface documents and this control board.

## P39 Reflection

`LAB-IGNITER-WEB-LIVE-BIND-HUMAN-GATED-PROOF-P39` closed the last active A10
tail as a lab authorization proof:

- `igweb-serve live-bind-proof --host-config PATH [--addr HOST:PORT]`;
- exact human acknowledgement:
  `IGNITER_LIVE_BIND_HUMAN_ACK=I_UNDERSTAND_IGNITER_LAB_LIVE_BIND_P39`;
- requires non-loopback addr, `terminated_upstream`, `trusted_proxy_only`, and
  the P37 verifier-backed checklist;
- calls pure `authorize_bind(addr, Some(checklist))`;
- prints `bind_attempted=false socket_opened=false public_bind=closed`.

A10 is therefore **closed for lab proof**. Production public bind remains
closed/deferred because normal `igweb-serve run` still calls
`authorize_bind(addr, None)`, native TLS is not implemented, and P39 opens no
listener.

## Remaining Deferred / Parallel Lanes

| Row | State | Why it does not block audit exit |
|---|---|---|
| A12 compiler lock default-on | Partly closed / deferred | `--locked`/`--frozen` exist; default-on waits for registry/signing/remote-source pressure. |
| A22 det_* cross-arch claim | Queued / external science lane | Evidence belongs to emergence/science T1/T2 work; not a foundation-audit blocker. |
| A24 frame-ui IDE/product preview | Queued / parallel frame-ui lane | Active frame-ui work continues separately; not mixed into foundation audit. |

## Stale Blocker Warnings

Agents should not reopen these from older packets without fresh live evidence:

- public bind is not accidentally enabled by `[host.live_bind]`;
- `live-bind-check` and `live-bind-proof` do not open sockets;
- `igweb-serve` async machine runner exists for DB/effect paths;
- multi-source read config exists for a single DSN;
- typed Todo JSON routes no longer depend on legacy `rows_json`.

## Recommended Next Wave

Return to non-audit work:

- Todo API / HTML payoff;
- frame-ui view/game/product work;
- science/emergence determinism and experiment lanes;
- command-center / DX packaging.

Start a new audit wave only if live source or a fresh external review produces
a concrete regression or an unowned blocker.
