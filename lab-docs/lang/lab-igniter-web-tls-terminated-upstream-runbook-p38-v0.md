# LAB-IGNITER-WEB-TLS-TERMINATED-UPSTREAM-RUNBOOK-P38 v0

Status: DONE
Date: 2026-06-28
Route: standard / main-audit / igniter-web / live-bind gate / TLS runbook
Card: `LAB-IGNITER-WEB-TLS-TERMINATED-UPSTREAM-RUNBOOK-P38`

## Scope

This packet closes the A10 operator-story gap for the first
`inbound_tls.mode = "terminated_upstream"` proof. It does not implement native
TLS transport, does not add certificate handling, does not open a public
listener, and does not grant bind authority.

Public bind remains closed in IgWeb v0.

## Live Surface Characterization

P33 defines the server-owned `LiveBindChecklist` and the pure
`authorize_bind` gate. Loopback binds need no checklist. Non-loopback binds
without a checklist fail closed. A complete checklist can include
`inbound_tls.mode = terminated_upstream` or `native_tls`, but this is gate
metadata only. Native TLS has no server transport today.

P35 keeps public bind on HOLD. Before any non-loopback listener, host state
must be converted into a checklist from verified runtime facts, a durable
signed-passport verifier must be wired, the TLS decision must be accepted, and a
human must approve the proof. P35 selected `terminated_upstream` as the first
acceptable TLS posture for a lab proof; `native_tls` remains blocked until a
real TLS accept path exists.

P36 adds `igweb-serve live-bind-check --host-config PATH [--addr HOST:PORT]`.
It parses `[host.live_bind]`, maps it to `LiveBindChecklist`, calls the pure
gate, and prints a report with `socket_opened=false public_bind=closed`. It is a
dry-run only. It never binds and grants no bind authority.

Current worktree source also contains P37 verifier loading in the dry-run path:
for non-loopback checklist evaluation, `live_bind_check.rs` loads and validates
durable signed-passport verifier material before setting
`signed_passport_path_wired`. That is P37 backing. It still opens no socket and
does not wire the real `Run` bind path.

Current source confirms the same boundary:

- `server/igniter-server/src/serving_gate.rs` is pure gate logic only.
- `server/igniter-web/src/host_config.rs` parses the checklist and rejects
  missing or malformed TLS fields before bind.
- `server/igniter-web/src/live_bind_check.rs` reports gate verdicts only and
  keeps real bind authority out of the dry-run surface.
- `server/igniter-web/IMPLEMENTED_SURFACE.md` states that public listener mode
  is closed and no TLS transport exists in IgWeb v0.

## `terminated_upstream` Meaning

In Igniter v0, `terminated_upstream` means:

1. A trusted operator-controlled proxy, load balancer, or local TLS terminator
   accepts the client TLS connection before traffic reaches IgWeb.
2. IgWeb receives upstream HTTP from that trusted terminator over a controlled
   path such as loopback, a private lab network, or a firewall-allowlisted link.
3. IgWeb itself does not perform a TLS handshake, does not read certificates,
   does not validate SNI, and does not derive client identity from TLS.
4. The config field is an operator assertion plus checklist input, not proof by
   itself.

This is therefore a termination assertion, not TLS transport.

## Transport, Assertion, Hints

TLS transport is a server capability: the server accepts TLS, owns certificate
configuration, and validates the handshake before HTTP dispatch. IgWeb does not
have this capability today. `native_tls` is therefore deferred.

TLS termination assertion is an operator contract: the operator asserts that TLS
is terminated upstream and that direct, untrusted access to the IgWeb upstream
socket is blocked. The assertion can feed the live-bind checklist, but the
first proof must still be human-gated and lab-only.

Header hints are observability only unless the request is already known to have
arrived from a trusted upstream boundary. Headers such as `Forwarded`,
`X-Forwarded-Proto`, `X-Forwarded-Host`, and `X-Forwarded-For` can be recorded
as hints for diagnostics. They are not authority when supplied by an arbitrary
direct client.

No header proves TLS by itself in v0.

## Trusted Header Policy

The v0 policy value is a conservative label:

```toml
[host.live_bind.inbound_tls]
mode = "terminated_upstream"
upstream_header_policy = "trusted_proxy_only"
```

`trusted_proxy_only` means:

- the operator owns the proxy/LB configuration;
- the proxy terminates TLS before forwarding to IgWeb;
- the proxy strips or overwrites client-supplied forwarding headers;
- IgWeb is reachable only from the trusted upstream path during the proof;
- direct client access to the IgWeb upstream socket is blocked or refused.

The policy string is not a secret, not a list of trusted IPs, and not proof.
It is a checklist label that P39 must back with topology evidence.

Untrusted direct-client headers must be ignored as authority. If a direct client
can connect to IgWeb and send `X-Forwarded-Proto: https`, that is a failed
termination proof, not TLS evidence.

## First P39 Topology

The first acceptable P39 proof is still lab-only and human-gated. It must make
no production claim.

Recommended sequence:

1. Rehearse the contract with a localhost reverse proxy. This proves the
   operator runbook and header overwrite behavior without needing an IgWeb
   non-loopback listener.
2. If P39 specifically needs a non-loopback bind proof, use a LAN-only lab
   proxy on an isolated/private network. The proof must include a firewall or
   listener rule showing that only the proxy can reach IgWeb upstream, plus a
   negative direct-client probe.
3. Do not use an external internet-facing LB for v0 P39. That remains outside
   this readiness lane.

## P39 Preconditions

P39 must include all of the following before any non-loopback listener proof:

- P36 dry-run evidence for the target config and address, with
  `mode = "terminated_upstream"`, `verdict=would_authorize`,
  `socket_opened=false`, and `public_bind=closed`.
- P37 durable signed-passport verifier evidence from host-verified backing, not
  only operator text. In the current worktree, this is represented by
  `live_bind_check.rs` verifier loading, but P39 must still include the
  evidence receipt.
- A secret-free proxy/LB topology statement naming whether the proof is
  localhost-rehearsal or LAN-only lab proxy.
- Evidence that TLS terminates at the trusted upstream component.
- Evidence that the proxy strips or overwrites forwarding headers before
  sending to IgWeb.
- A negative direct-client check showing untrusted clients cannot reach the
  IgWeb upstream socket or cannot influence trusted forwarding headers.
- Listener evidence before, during, and after the proof, with rollback back to
  loopback/closed state.
- Explicit human approval for the time-boxed proof.
- Logs or receipts that avoid inline secrets, bearer tokens, private keys,
  certificate material, DSNs, and full unredacted client identifiers.
- A refusal note if the config uses `native_tls`; native TLS is blocked until a
  real TLS transport card exists.

## `live-bind-check` Expectations

For `terminated_upstream`, `live-bind-check` should report only the structural
gate verdict. A `would_authorize` result means the parsed checklist satisfies
the pure server gate for the requested address. It does not mean a trusted
terminator was observed, does not mean TLS is active, and does not open a
socket.

For malformed `terminated_upstream`, such as a missing
`upstream_header_policy`, parsing should fail closed before any dry-run verdict.

For `native_tls`, current parser and dry-run code can accept complete
certificate/key file references as checklist metadata. With valid P37 verifier
backing, the pure server gate can structurally authorize that metadata. P39
must still refuse `native_tls` for an actual non-loopback proof with the
reason:

```text
native_tls transport is not implemented in IgWeb v0
```

For malformed `native_tls`, such as a missing cert/key reference, parsing should
fail closed before any dry-run verdict.

For `mode = "none"`, parsing should fail closed. There is no no-TLS live-bind
mode.

## Refusal Boundaries

- No native TLS accept path is implemented or implied.
- No certificate, ACME, rustls, proxy-protocol, or public deployment behavior is
  added by this packet.
- No forwarding header is trusted from arbitrary clients.
- No production/external-LB claim is made.
- No public or non-loopback listener was opened for this card.

## Verification

Doc/readiness-only pass:

```bash
git diff --check
```

No runtime tests are required because no runtime code changed.
