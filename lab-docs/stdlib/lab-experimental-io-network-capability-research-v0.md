# Lab: Experimental IO.NetworkCapability — Research (v0)

> Status: experimental · lab-only · research-only · no implementation
> Card: LAB-STDLIB-NET-P1
> Date: 2026-06-07
> Track: lab-experimental-io-network-capability-research-v0
> Route: EXPERIMENTAL / LAB-ONLY / RESEARCH
> Depends on: LAB-STDLIB-IO-P1 through P10, LAB-RACK-P1

---

## Pre-v1 Language Note

Igniter Lang is under active development. All constructs described in this
document — including capability schemas, delegation algebra extensions, effect
surface shapes, and stdlib interface sketches — are drawn from proposed or
accepted spec chapters and the established IO capability lab pattern (P1–P10).
They are not stable APIs. Syntax shown as "Illustrative only — not canon syntax"
reflects the current spec vocabulary but has not been verified as finalized
grammar. This document is lab-only research evidence. It does not constitute
canon specification, a PROP, or a production commitment. The source
`igniter-lang` documents remain the reference for all formal decisions.

---

## 1. Motivation and Upstream Pressure

### 1.1 Why Network I/O?

LAB-RACK-P1 identified network I/O as the single highest-priority blocking gap
for any server-layer Igniter construct (Rack-equivalent, HTTP handler, service
loop). The feasibility matrix in LAB-RACK-P1 §3 records `IO.NetworkCapability`
as `LOW` expressibility with status `BLOCKED` and `NOT STARTED`. Specifically,
LAB-RACK-P1 §5.1 states:

> "Igniter has no TCP socket or network I/O in its stdlib or runtime."

The file IO capability system (P1–P10) proved the sandbox + delegation algebra
for local filesystem access. Every layer of that work — the capability schema
(P1), the effect surface binding (P2), the runtime dry-run (P3), the delegation
algebra (P4), the manifest hardening (P5), the compiler-passport bridge (P6),
the schema generalization (P7), the VM loader integration (P8), the static
loader alignment hardening (P9), and the end-to-end observability slice (P10)
— established a repeatable pattern for named, scoped, delegatable, auditable
I/O capabilities.

Network I/O needs the same accountability treatment, as required by:
- **Covenant Axiom 1 (Honesty)**: a program that opens a TCP connection without
  naming it cannot give an honest account of what it does to the world.
- **Covenant Postulate 4 (Named Effects)**: every side effect is named; there
  is no I/O without a declaration.
- **Covenant Postulate 7 (No Hidden Consequences)**: a reader of the contract
  header must be able to know the full consequence — including which hosts and
  ports the contract may reach.
- **Covenant Postulate 8 (Receipts Are Proof)**: every network operation must
  produce a receipt as immutable proof of what occurred.
- **Covenant Postulate 21 (Consequence Ownership)**: a program owns its
  consequences; a network call to an external host is a consequence that must
  be named.

### 1.2 What Changes from File IO?

File IO scope is **spatial** (directory sandbox, path allowlist). Network IO
scope is **topological** (host allowlist, port ranges, protocol constraints).

The file IO capability schema from P1 carries:
- `sandbox_dir` — the spatial container
- `allowed_absolute_paths` — explicit path escapes from the sandbox
- `read_allowed` / `write_allowed` — permission bits

Network IO has no "sandbox directory" analog. Its scope dimensions are
fundamentally different:

| Dimension | File IO | Network IO |
|---|---|---|
| Container | `sandbox_dir` (directory) | (host, port, protocol) triple |
| Exclusions | `allowed_absolute_paths` | `allowed_hosts` (explicit allowlist) |
| Permissions | `read_allowed`, `write_allowed` | `connect_allowed`, `listen_allowed`, `send_allowed`, `receive_allowed` |
| Containment policy | Sandbox Bound | Loopback Bound |
| Path constraint | Path Traversal Block | Port Range Check |
| Escalation guard | Absolute Path Block | Host Allowlist Check |
| Mode check | Explicit Permissions | Explicit Direction Check |
| New dimension | — | TLS enforcement, protocol layer, bind address |

Key design differences requiring new schema fields:

- **No sandbox directory analog** — network scope is defined by (host, port,
  protocol) triples, not by a directory path.
- **Directionality matters** — `connect` (outbound) and `listen` (inbound) are
  distinct operations with different security profiles. A loopback service and
  an external API client have nothing in common despite both being "network IO".
- **Protocol layer** — TCP vs UDP vs tcp_udp carry different capability profiles.
  A UDP datagram sender should not be grantable as a TCP stream listener.
- **Binding address** — what local interface may be bound? Loopback only, or
  any interface?
- **Peer identity** — what remote hosts are permitted? Exact match or glob.
- **Port range** — what port numbers are in scope? Ranges rather than exact
  values, to support realistic service configurations.
- **Loopback isolation** — a "loopback-only" capability is the network
  equivalent of a sandbox bound: it prevents the capability from being used to
  reach external hosts, even if the capability holder is compromised.
- **TLS enforcement** — a new security dimension with no file IO analog: the
  protocol layer may be required to be encrypted. Plaintext connections to an
  HTTPS-only external service should fail closed.

---

## 2. IO.NetworkCapability Schema Design

### 2.1 Core Schema

The `IO.NetworkCapability` JSON schema is analogous to the `IO.Capability`
(file) schema established in LAB-STDLIB-IO-P1 and generalized in
LAB-STDLIB-IO-P7.

```json
{
  "capability_id": "cap-net-01",
  "resource_type": "network",
  "protocol": "tcp",
  "direction": "connect",
  "bind_address": "127.0.0.1",
  "allowed_hosts": ["127.0.0.1", "localhost"],
  "allowed_port_ranges": [
    { "min": 8000, "max": 9000 }
  ],
  "loopback_only": true,
  "connect_allowed": true,
  "listen_allowed": false,
  "send_allowed": true,
  "receive_allowed": true,
  "tls_required": false
}
```

The `resource_type: "network"` discriminator enables the runtime to select the
correct validation policy set (network policy NET-1 through NET-6, not file
policy P1–P4). This follows the generalization established in LAB-STDLIB-IO-P7
§1 ("Removes the Forced Alias … preserves the exact declared capability names
as keys") and extends it to the multi-resource-type case.

### 2.2 Field Definitions

Every field is documented below with its type, requirement, description, and
its analog in the file IO capability schema.

| Field | Type | Required | Description | File IO analog |
|---|---|---|---|---|
| `capability_id` | String | yes | Unique identifier for this capability grant instance | `capability_id` (P1) |
| `resource_type` | String (`"network"`) | yes | Resource type discriminator; enables runtime policy dispatch | `"file"` value in P7 generalized schema |
| `protocol` | String (`"tcp"` \| `"udp"` \| `"tcp_udp"`) | yes | Transport protocol layer permitted for this capability | no file IO analog — new field |
| `direction` | String (`"connect"` \| `"listen"` \| `"both"`) | yes | Whether this capability permits outbound connect, inbound listen, or both | directional analog to `read_allowed`/`write_allowed` |
| `bind_address` | String \| null | no | Local interface to bind when listening (null = OS chooses) | `sandbox_dir` analog — local constraint on what the capability can bind |
| `allowed_hosts` | Array[String] | yes | Permitted remote hosts; exact match or glob; empty = all blocked (fail-closed) | `allowed_absolute_paths` analog — explicit scope of reachable remotes |
| `allowed_port_ranges` | Array[{min: Integer, max: Integer}] | yes | Permitted port numbers as inclusive ranges; empty = all blocked | path restriction analog — containment constraint on reachable ports |
| `loopback_only` | Bool | yes | If true, any connection to a non-loopback address fails closed (Policy NET-1) | `sandbox_bound` containment policy analog |
| `connect_allowed` | Bool | yes | May initiate outbound connections | `read_allowed` analog (initiating a connection to read/write data) |
| `listen_allowed` | Bool | yes | May bind a port and accept inbound connections | `write_allowed` analog (binding a port has external consequence) |
| `send_allowed` | Bool | yes | May send data over an established connection | sub-permission within a direction |
| `receive_allowed` | Bool | yes | May receive data over an established connection | sub-permission within a direction |
| `tls_required` | Bool | no | If true, plaintext (non-TLS) connection attempts fail closed (Policy NET-5) | no file IO analog — new security constraint |

**Fail-closed defaults**: an empty `allowed_hosts` array means all hosts are
blocked. An empty `allowed_port_ranges` array means all ports are blocked.
These fail-closed defaults mirror the Absolute Path Block (Policy 3 in P1):
explicit enumeration is required to open access, not the reverse.

### 2.3 Variant Schemas

Three named variants cover the primary use cases in the Rack feasibility study
and the loopback-first safety stance of the IO lab.

**Variant A: Loopback-only connect (tightest — proof-local default)**

The safest variant: no external network exposure, suitable for proof runner
validation and inter-process communication on the same machine.

```json
{
  "capability_id": "cap-net-loopback-connect",
  "resource_type": "network",
  "protocol": "tcp",
  "direction": "connect",
  "bind_address": "127.0.0.1",
  "allowed_hosts": ["127.0.0.1", "localhost"],
  "allowed_port_ranges": [{ "min": 1024, "max": 65535 }],
  "loopback_only": true,
  "connect_allowed": true,
  "listen_allowed": false,
  "send_allowed": true,
  "receive_allowed": true,
  "tls_required": false
}
```

**Variant B: Localhost listen (service loop candidate)**

The inbound listen variant: binds to loopback only, accepts connections from
any local client. This is the capability shape for a loopback HTTP service loop
— the first step toward a Rack-equivalent proof runner target.

```json
{
  "capability_id": "cap-net-localhost-listen",
  "resource_type": "network",
  "protocol": "tcp",
  "direction": "listen",
  "bind_address": "127.0.0.1",
  "allowed_hosts": ["*"],
  "allowed_port_ranges": [{ "min": 3000, "max": 9999 }],
  "loopback_only": true,
  "connect_allowed": false,
  "listen_allowed": true,
  "send_allowed": true,
  "receive_allowed": true,
  "tls_required": false
}
```

**Variant C: External HTTPS-only connect (restricted outbound)**

An outbound-only capability scoped to specific external hosts on port 443,
with TLS enforcement. This is the capability shape for a restricted outbound
API client — analogous to an `allowed_absolute_paths`-restricted file read.

```json
{
  "capability_id": "cap-net-https-outbound",
  "resource_type": "network",
  "protocol": "tcp",
  "direction": "connect",
  "bind_address": null,
  "allowed_hosts": ["api.example.com", "cdn.example.com"],
  "allowed_port_ranges": [{ "min": 443, "max": 443 }],
  "loopback_only": false,
  "connect_allowed": true,
  "listen_allowed": false,
  "send_allowed": true,
  "receive_allowed": true,
  "tls_required": true
}
```

---

## 3. Safety Policies (Network Analogs to File IO Policies)

The four file IO safety policies from LAB-STDLIB-IO-P1 §2 (Sandbox Bound, Path
Traversal Block, Absolute Path Block, Explicit Permissions) have direct network
analogs, plus two new policies for network-specific security dimensions.

### Policy NET-1: Loopback Bound

**Description**: When `loopback_only: true`, any connection attempt to a
non-loopback address (not `127.x.x.x`, not `::1`, not `"localhost"`) fails
closed immediately.

**What it prevents**: An attacker or a buggy delegation cannot use a
loopback-scoped capability to reach an external host. Even if the capability
is delegated to a compromised sub-contract, the loopback constraint travels
with the grant.

**Error code**: `E-NET-LOOPBACK-VIOLATION`

**File IO analog**: Sandbox Bound (P1 Policy 1 — `SandboxSecurityViolation`).
The loopback address space plays the role of the sandbox directory: it is a
spatial containment that cannot be escaped by any operation within the grant.

---

### Policy NET-2: Host Allowlist Check

**Description**: Every remote host targeted by a connection or listen attempt
must match at least one entry in `allowed_hosts`. Matching is by exact string
comparison or glob pattern. An empty `allowed_hosts` array means all hosts are
blocked (fail-closed default).

**What it prevents**: A contract holding a loopback connect capability cannot
be used to connect to `10.0.0.1` or any external host not in the allowlist,
even if `loopback_only` is false.

**Error code**: `E-NET-HOST-BLOCKED`

**File IO analog**: Absolute Path Block (P1 Policy 3). An absolute path is
allowed only if it appears in `allowed_absolute_paths`; a remote host is
allowed only if it appears in `allowed_hosts`.

---

### Policy NET-3: Port Range Check

**Description**: Every connection or listen port must fall within at least one
inclusive range in `allowed_port_ranges`. An empty `allowed_port_ranges` array
means all ports are blocked.

**What it prevents**: A web outbound capability scoped to port 443 cannot be
used to connect to port 22 (SSH), port 25 (SMTP), or any other out-of-range
port, even if the target host is permitted.

**Error code**: `E-NET-PORT-BLOCKED`

**File IO analog**: Path Traversal Block (P1 Policy 2). As path traversal
containment ensures the resolved path stays within the sandbox, port range
containment ensures the target port stays within the declared scope.

---

### Policy NET-4: Explicit Direction Check

**Description**: Operations must match declared direction permissions:
- `connect` operations require `connect_allowed: true`.
- `listen` (bind + accept) operations require `listen_allowed: true`.
- `send` operations require `send_allowed: true`.
- `receive` operations require `receive_allowed: true`.

Any operation using a direction not enabled in the capability fails closed.

**Error code**: `E-NET-DIRECTION-BLOCKED`

**File IO analog**: Explicit Permissions (P1 Policy 4 — `E-IO-CAP-WRONG-MODE`).
A read-only file capability cannot be used for writes; a connect-only network
capability cannot be used to listen.

---

### Policy NET-5: TLS Enforcement (new — no file IO analog)

**Description**: When `tls_required: true`, any plaintext (non-TLS) connection
attempt fails closed. The capability holder must negotiate TLS before any data
is exchanged.

**What it prevents**: An API client capability scoped to `api.example.com:443`
with `tls_required: true` cannot be used to establish an unencrypted connection
to that host, even if the host accepts plaintext on the same port. Downgrade
attacks are blocked at the capability layer.

**Error code**: `E-NET-TLS-REQUIRED`

**File IO analog**: no direct analog. This is a network-specific policy
addressing transport-layer security — a dimension that does not exist for local
filesystem operations.

---

### Policy NET-6: Protocol Constraint (new — no file IO analog)

**Description**: Operations using a protocol not matching the declared
`protocol` field fail closed. A `"tcp"` capability cannot be used for UDP
datagrams. A `"udp"` capability cannot be used for TCP stream connections.
A `"tcp_udp"` capability permits both.

**What it prevents**: A low-privilege UDP capability cannot be misused to
establish a TCP stream connection, which has fundamentally different connection
state, ordering guarantees, and security profile.

**Error code**: `E-NET-PROTOCOL-MISMATCH`

**File IO analog**: no direct analog. Protocol layer is a network-specific
dimension.

---

## 4. Extended Delegation Algebra

The file IO delegation algebra is defined in LAB-STDLIB-IO-P4 §3 as the
sub-grant ordering relation (G₂ ⊑ G₁). This section extends that algebra
to network capability grants, preserving the same non-escalation principle:
a delegated grant may only restrict, never expand, the parent grant's scope.

### 4.1 Network Grant Definition

A NetworkCapabilityGrant is:

```
G_net = <id, resource_type, protocol, direction, scope_net, permissions_net, tls_required>
```

Where:

```
scope_net        = <bind_address, allowed_hosts, allowed_port_ranges, loopback_only>
permissions_net  = <connect_allowed, listen_allowed, send_allowed, receive_allowed>
```

This parallels the file grant definition from LAB-STDLIB-IO-P4 §3:

```
G = <id, resource_type, scope, permissions>
where scope       = <sandbox_dir, allowed_absolute_paths>
      permissions = <read_allowed, write_allowed>
```

### 4.2 Sub-Grant Ordering Relation (G₂ ⊑_net G₁)

G₂ is a valid delegation of G₁ if and only if all eight conditions hold:

**Condition 1 — Type Identity:**

```
G₂.resource_type == G₁.resource_type == "network"
```

Same as the file IO Type Identity condition (LAB-STDLIB-IO-P4 §3, Condition 1).
A network grant cannot be delegated as a file grant and vice versa.

**Condition 2 — Protocol Non-Escalation:**

```
G₂.protocol ⊆ G₁.protocol
```

Where the subset relation on protocol values is:
- `"tcp"` ⊑ `"tcp_udp"` (TCP-only refines tcp+udp)
- `"udp"` ⊑ `"tcp_udp"` (UDP-only refines tcp+udp)
- `"tcp"` ⊑ `"tcp"` (same protocol)
- `"udp"` ⊑ `"udp"` (same protocol)
- `"tcp"` is NOT ⊑ `"udp"` (protocol mismatch — not a valid delegation)
- `"tcp_udp"` is NOT ⊑ `"tcp"` (escalation — parent only permits TCP)

**Condition 3 — Direction Non-Escalation:**

```
G₂.connect_allowed  → G₁.connect_allowed
G₂.listen_allowed   → G₁.listen_allowed
G₂.send_allowed     → G₁.send_allowed
G₂.receive_allowed  → G₁.receive_allowed
```

A delegation cannot gain a direction the parent does not hold. A
connect-only parent cannot delegate a grant with `listen_allowed: true`.
This directly mirrors the file IO Permission Non-Escalation condition
(LAB-STDLIB-IO-P4 §3, Condition 2):
`G₂.write_allowed → G₁.write_allowed`.

**Condition 4 — Loopback Non-Escalation:**

```
G₁.loopback_only == true  →  G₂.loopback_only == true
```

A loopback-only grant cannot be delegated as a non-loopback grant. Once the
loopback containment is set, it is hereditary through the delegation chain.
This mirrors the Sandbox Inclusion condition (LAB-STDLIB-IO-P4 §3, Condition 3):
the delegated sandbox must be equal to or nested within the parent sandbox.

**Condition 5 — Host Scope Inclusion:**

```
G₂.allowed_hosts ⊆ G₁.allowed_hosts
```

The delegated host set must be a subset of the parent's host set. A delegation
may only include hosts that the parent grant already permits. Exception: if
G₁.allowed_hosts contains a glob (e.g., `"*.example.com"`), G₂ may refine it
to specific subdomains (e.g., `"api.example.com"`).

This mirrors the Allowed Paths Subset condition (LAB-STDLIB-IO-P4 §3, Condition 3):
`G₂.allowed_absolute_paths ⊆ G₁.allowed_absolute_paths`.

**Condition 6 — Port Range Inclusion:**

For every range `[min₂, max₂]` in G₂.allowed_port_ranges, there must exist
a range `[min₁, max₁]` in G₁.allowed_port_ranges such that:

```
min₁ ≤ min₂  AND  max₂ ≤ max₁
```

Delegated port ranges must be subsets of parent port ranges. A delegation
cannot open a port range that the parent does not already permit.

**Condition 7 — TLS Non-Downgrade:**

```
G₁.tls_required == true  →  G₂.tls_required == true
```

A TLS-required grant cannot be delegated to a grant that permits plaintext.
TLS enforcement may be inherited (parent required, child required) or
strengthened (parent not required, child requires it) — never relaxed.

**Condition 8 — Bind Address Non-Escalation:**

```
G₁.bind_address != null  →  G₂.bind_address == G₁.bind_address  OR  G₂.bind_address == null
```

A delegation cannot bind to a different interface than the parent. If the
parent is locked to `127.0.0.1`, the child cannot bind to `0.0.0.0`. A null
child bind_address means "OS chooses within the parent's constraint" — this is
permitted.

### 4.3 Compose Operator (G₁ ∧ G₂)

The meet (intersection) of two network grants is used when two middleware
layers each apply constraints to the same capability. The resulting grant is
the most restrictive interpretation of both.

```
(G₁ ∧ G₂).allowed_hosts        = G₁.allowed_hosts ∩ G₂.allowed_hosts
(G₁ ∧ G₂).allowed_port_ranges  = pairwise intersection of port ranges
(G₁ ∧ G₂).connect_allowed      = G₁.connect_allowed AND G₂.connect_allowed
(G₁ ∧ G₂).listen_allowed       = G₁.listen_allowed AND G₂.listen_allowed
(G₁ ∧ G₂).send_allowed         = G₁.send_allowed AND G₂.send_allowed
(G₁ ∧ G₂).receive_allowed      = G₁.receive_allowed AND G₂.receive_allowed
(G₁ ∧ G₂).loopback_only        = G₁.loopback_only OR G₂.loopback_only
(G₁ ∧ G₂).tls_required         = G₁.tls_required OR G₂.tls_required
(G₁ ∧ G₂).protocol             = most restrictive common protocol
```

The loopback and TLS fields take the more restrictive value (OR): if either
grant requires loopback or TLS, the composed grant inherits that requirement.
Permissions (connect, listen, send, receive) take the intersection (AND): a
composed grant only has a permission if both constituent grants have it.

This compose operator corresponds to the
`ESCAPE ∘ ESCAPE` composition algebra in LAB-STDLIB-IO-P4 §3
("Disjoint Capabilities" / "Dynamic Delegation").

### 4.4 Violation Classes (Delegation Failures)

| Violation | Condition | Error code |
|---|---|---|
| Protocol escalation | G₂.protocol not ⊆ G₁.protocol | `E-NET-DELEGATION-PROTOCOL-ESCALATION` |
| Permission escalation | G₂ permission bit > G₁ permission bit (any of connect/listen/send/receive) | `E-NET-DELEGATION-PERMISSION-ESCALATION` |
| Loopback escape | G₁.loopback_only == true, G₂.loopback_only == false | `E-NET-DELEGATION-LOOPBACK-ESCAPE` |
| Host escape | G₂.allowed_hosts ⊄ G₁.allowed_hosts | `E-NET-DELEGATION-HOST-ESCAPE` |
| Port escape | G₂ port range ⊄ any G₁ port range | `E-NET-DELEGATION-PORT-ESCAPE` |
| TLS downgrade | G₁.tls_required == true, G₂.tls_required == false | `E-NET-DELEGATION-TLS-DOWNGRADE` |
| Bind escalation | G₁.bind_address != null, G₂.bind_address differs from G₁.bind_address | `E-NET-DELEGATION-BIND-ESCALATION` |

These seven violation classes are the network counterparts of the four
violation classes implicit in the file IO delegation algebra (P4, P5, P8, P9).
The loopback, TLS, host, and port escape classes are new — they have no file IO
analog because the file IO scope model does not have those dimensions.

The runtime must check all seven conditions atomically before allowing a
delegation. Partial passes are not permitted. Any single condition failure
must trigger the corresponding error code and abort the call boundary
(see LAB-STDLIB-IO-P5 §4: "Execution Log Telemetry — Every boundary check
writes to a dynamic receipt log").

---

## 5. Effect Surface Binding (Illustrative — Not Canon Syntax)

This section shows how `IO.NetworkCapability` would bind to Igniter's effect
surface declaration, following the pattern established in LAB-STDLIB-IO-P2.
**All code in this section is labeled: "Illustrative only — not canon syntax."**
PROP-035 (Effect Surface) has not yet been authored or accepted.

### 5.1 Capability Declaration Syntax (Illustrative)

```igniter
-- Illustrative only — not canon syntax
capability net_outbound: IO.NetworkCapability
capability net_listen: IO.NetworkCapability
```

This follows the syntax introduced in LAB-STDLIB-IO-P2 §2:
```
capability io_file_read: IO.Capability
```

The capability keyword declares a named, typed capability that the contract
requires at runtime to perform specific side effects. For network capabilities,
the type is `IO.NetworkCapability` rather than `IO.Capability`, enabling the
runtime to apply the network policy set (NET-1 through NET-6) rather than the
file policy set.

### 5.2 Effect Binding (Illustrative)

```igniter
-- Illustrative only — not canon syntax
effect connect_to_peer using net_outbound
effect accept_connection using net_listen
```

This follows the syntax introduced in LAB-STDLIB-IO-P2 §2:
```
effect read_file using io_file_read
```

The `using` keyword binds a logical effect name to a declared capability. A
contract that declares `capability net_outbound: IO.NetworkCapability` but has
no `effect ... using net_outbound` binding would trigger
`E-NET-EFFECT-UNDECLARED` (analogous to `E-IO-EFFECT-UNDECLARED` from
LAB-STDLIB-IO-P2 §3).

### 5.3 Full Effect Contract Shape (Illustrative)

```igniter
-- Illustrative only — not canon syntax
effect contract FetchRemoteData(
  url: String,
  net: IO.NetworkCapability
) -> Result[String, NetworkError]
  affects external HTTP.RemoteEndpoint
  authority network_operator
  reversibility :reversible
  idempotency natural
  receipt NetworkFetchReceipt
  failure NetworkError
```

The `affects external HTTP.RemoteEndpoint` clause satisfies Covenant Postulate 7
(No Hidden Consequences): a reader of the contract header sees that this
contract reaches an external HTTP endpoint without inspecting the body.

The `reversibility :reversible` declaration follows ch12 §12.3: a GET-style
fetch can be repeated without consequence. A POST-equivalent would require
`:compensatable` or a deduplication key, as analyzed in LAB-RACK-P1 §2.5.

### 5.4 Compiler Classification

Network I/O nodes, like file I/O nodes established in LAB-STDLIB-IO-P2 §4,
must be classified as `escape` (not `core`). LAB-STDLIB-IO-P2 §1 states:

> "Computations calling `stdlib.IO.*` are classified as `'escape'` rather than
> `'core'` nodes, mapping them cleanly to escape/effect boundaries."

The same classification applies to `stdlib.io.network.*` calls. No network
operation can be `core` because:
- Network is non-deterministic (same call may return different results)
- Network has external consequence (Covenant Postulate 7)
- Network requires explicit capability (Covenant Postulate 4)
- Network timeout is `UnknownExternalOutcome`, not `ObservedFailure` (Postulate 15)

Proposed error codes for network capability violations, analogous to the file IO
error codes defined in LAB-STDLIB-IO-P2 §3:

| Code | Trigger | File IO analog |
|---|---|---|
| `E-NET-AMBIENT-BLOCKED` | Network call in a pure contract with no capability declared | `E-IO-AMBIENT-BLOCKED` |
| `E-NET-CAP-MISSING` | Network call missing its capability argument | `E-IO-CAP-MISSING` |
| `E-NET-CAP-UNKNOWN` | Capability argument passed to a network call is not declared in the contract | `E-IO-CAP-UNKNOWN` |
| `E-NET-EFFECT-UNDECLARED` | Capability declared but no `effect ... using` binding | `E-IO-EFFECT-UNDECLARED` |
| `E-NET-DIRECTION-BLOCKED` | Wrong direction used (connect on listen-only, listen on connect-only) | `E-IO-CAP-WRONG-MODE` |
| `E-NET-HOST-BLOCKED` | Target host not in `allowed_hosts` | new — no file IO analog |
| `E-NET-PORT-BLOCKED` | Target port not in `allowed_port_ranges` | new — no file IO analog |
| `E-NET-LOOPBACK-VIOLATION` | Non-loopback attempt when `loopback_only: true` | new — no file IO analog |
| `E-NET-TLS-REQUIRED` | Plaintext connection when `tls_required: true` | new — no file IO analog |
| `E-NET-PROTOCOL-MISMATCH` | Operation uses wrong protocol for capability | new — no file IO analog |

---

## 6. Passport Schema Extension

The generalized passport schema from LAB-STDLIB-IO-P7 §2 introduces the
`capability_bindings` top-level section and the `resource_type` field per
capability. This section extends that schema to include `IO.NetworkCapability`
grants alongside `IO.Capability` (file) grants in a single passport.

### 6.1 Extended Passport with Network Grants

```json
{
  "runtime_implementation_id": "igniter.delegated.experimental.io.network.v0",
  "backend_implementation_id": "none",
  "consumer_surface_id": "igniter-lab",
  "surface_dimension": "runtime",
  "artifact_kind": "igapp_dir",
  "artifact_digest": "sha256:<hash>",
  "capability_bindings": {
    "net_outbound": "net_outbound",
    "io_file_read": "io_file_read"
  },
  "required_capabilities": {
    "net_outbound": {
      "capability_id": "cap-net-loopback-connect",
      "resource_type": "network",
      "protocol": "tcp",
      "direction": "connect",
      "bind_address": "127.0.0.1",
      "allowed_hosts": ["127.0.0.1", "localhost"],
      "allowed_port_ranges": [{ "min": 8000, "max": 9000 }],
      "loopback_only": true,
      "connect_allowed": true,
      "listen_allowed": false,
      "send_allowed": true,
      "receive_allowed": true,
      "tls_required": false,
      "sandbox_policy_source": "proof_default"
    },
    "io_file_read": {
      "capability_id": "cap-io-01",
      "resource_type": "file",
      "sandbox_dir": "out/sandbox",
      "allowed_absolute_paths": [],
      "read_allowed": true,
      "write_allowed": false,
      "sandbox_policy_source": "proof_default"
    }
  }
}
```

The `resource_type` discriminator field — introduced as the key generalization
in LAB-STDLIB-IO-P7 — enables the runtime VM loader (as established in
LAB-STDLIB-IO-P8 §1) to apply the correct validation policy per capability:
- `resource_type: "file"` → apply file IO safety policies (P1–P4)
- `resource_type: "network"` → apply network IO safety policies (NET-1–NET-6)

The `sandbox_policy_source: "proof_default"` label from LAB-STDLIB-IO-P7 §1
("Non-Canonical Sandbox Policy") is preserved: it explicitly marks these
entries as laboratory metadata rather than canonical syntax.

### 6.2 Resource Type Registry

Proposed registry of known `resource_type` values, extending the two-entry
implicit registry established by P1 (file) and this document (network):

| resource_type | Schema | Policy set | Lab card |
|---|---|---|---|
| `"file"` | P1 file capability schema | P1 file safety policies (Sandbox Bound, Path Traversal Block, Absolute Path Block, Explicit Permissions) | LAB-STDLIB-IO-P1 |
| `"network"` | Network capability schema (this document) | NET-1 through NET-6 | LAB-STDLIB-NET-P1 |
| `"env"` | (future) environment variable capability | (future) | TBD |
| `"process"` | (future) subprocess capability | (future) | TBD |
| `"clock"` | (future) real-time clock capability | (future) | TBD |

The `resource_type` registry is a lab-local enumeration for the experimental
capability system. It does not constitute a canonical type registry in
`igniter-lang`.

---

## 7. Stdlib Module Design Sketch

This section proposes what `stdlib/io/network.ig` would contain, analogous to
`stdlib/io/file.ig` from the P1–P10 lab work. **This is a design sketch only
— not implemented. No source code exists.**

### 7.1 Proposed stdlib/io/network.ig Operations

```
-- Design sketch — not implemented
stdlib.io.network.connect(host: String, port: Integer, cap: IO.NetworkCapability)
  -> Result[Connection, NetworkError]

stdlib.io.network.listen(bind_addr: String, port: Integer, cap: IO.NetworkCapability)
  -> Result[Listener, NetworkError]

stdlib.io.network.accept(listener: Listener, cap: IO.NetworkCapability)
  -> Result[Connection, NetworkError]

stdlib.io.network.send(conn: Connection, data: String, cap: IO.NetworkCapability)
  -> Result[SendReceipt, NetworkError]

stdlib.io.network.receive(conn: Connection, max_bytes: Integer, cap: IO.NetworkCapability)
  -> Result[String, NetworkError]

stdlib.io.network.close(conn: Connection, cap: IO.NetworkCapability)
  -> Result[CloseReceipt, NetworkError]
```

The capability argument is explicit and required on every call — just as in
the file IO FFI signatures (LAB-STDLIB-IO-P1 §3: `stdlib_io_read_text(path,
capability)`, `stdlib_io_write_text(path, content, capability)`). The runtime
validates the capability against the operation attempted before dispatching
to the underlying OS call. This design ensures ambient access is impossible:
a call without a capability argument cannot compile (E-NET-CAP-MISSING).

### 7.2 Result and Receipt Types (Design Sketch)

```
-- Design sketch — not implemented
type NetworkError {
  code: String           -- E-NET-* error code
  message: String
  host: Option[String]
  port: Option[Integer]
  capability_id: String  -- which capability was checked when the error occurred
}

type SendReceipt {
  connection_id: String
  bytes_sent: Integer
  timestamp: Timestamp
  capability_ref: String  -- capability_id that authorized this send
}

type CloseReceipt {
  connection_id: String
  timestamp: Timestamp
  capability_ref: String
}

type Connection {
  connection_id: String
  remote_host: String
  remote_port: Integer
  protocol: String
  established_at: Timestamp
}

type Listener {
  listener_id: String
  bind_address: String
  bind_port: Integer
  protocol: String
}
```

The `capability_ref` field in receipts (following Covenant Postulate 8:
"Receipts Are Proof") links the operation's audit record to the specific
capability grant that authorized it. This mirrors the `capability_id` field
in file IO receipts from LAB-STDLIB-IO-P1 §4:
`"capability_id": "cap-io-01"`.

### 7.3 Tier Classification

`stdlib/io/network.ig` would be classified as **ESCAPE** tier (like file I/O),
NOT CORE. This follows the tier classification established in ch8 §8.1:
```
stdlib/core/ — Tier 1: no TBackend reads, no FFI, no ambient clock → CORE
```

Network I/O fails every CORE condition:
- It requires FFI (OS socket syscalls).
- It is non-deterministic (results depend on external state).
- It has external consequence (Covenant Postulate 7).
- Network timeout maps to `UnknownExternalOutcome`, not `ObservedFailure`
  (Covenant Postulate 15) — a core execution cannot carry this failure class.

No network operation can be CORE, and any IR node classified as CORE that
calls a `stdlib.io.network.*` function is a compiler classification error.

---

## 8. Relationship to Rack Feasibility (LAB-RACK-P1)

LAB-RACK-P1 §5.1 ("Network I/O — Blocking Gap") stated:

> "Igniter has no TCP socket or network I/O in its stdlib or runtime."

The `IO.NetworkCapability` schema defined in this document is the required
first step toward addressing that gap. The relationship between this document
and the Rack feasibility study:

- **Loopback-only connect (Variant A)** is the proof-local safe default for
  any lab proof runner. It matches LAB-RACK-P1's observation that the lab needs
  a sandboxed, non-externally-exposed capability for proof development.

- **Localhost listen (Variant B)** with `listen_allowed: true` is the
  prerequisite capability shape for a Rack-style accept loop. Without a
  `listen_allowed` capability, no contract can bind a port and accept inbound
  connections. This is the minimal required shape for any HTTP server analog.

- **TLS enforcement (`tls_required: true`)** maps to Rack's SSL middleware
  (e.g., Rack::SSL). Where Rack adds TLS as optional middleware, Igniter
  encodes the TLS requirement in the capability grant — making it a named,
  auditable, delegation-aware property rather than an ambient middleware choice.

- **Host/port allowlist** maps to Rack's `allowed_hosts` middleware and
  firewall rules. Where Rack's middleware operates at the request-parsing layer,
  the Igniter allowlist operates at the capability layer — before any connection
  is established.

- **The delegation algebra (§4)** ensures middleware in a Rack-equivalent chain
  can only narrow, never expand, the network scope. A logging middleware that
  wraps a handler contract cannot gain `listen_allowed: true` if the parent
  handler only had `connect_allowed: true`. This satisfies LAB-RACK-P1 §4.6
  ("Named capabilities instead of ambient I/O access") at the algebra level.

- **The service loop blocker** remains. Even with `IO.NetworkCapability` defined,
  a Rack-equivalent still requires a ServiceLoop (ch13, PROP-039+, Stage 4
  deferred) to run `accept` repeatedly. This document resolves the capability
  shape gap but does not resolve the service loop gap. See LAB-RACK-P1 §5.2.

---

## 9. Relationship to Effect Surface (PROP-035)

PROP-035 defines the Effect Surface (ch12) including the `affects external`
clause, the `authority` field, the `reversibility` scale, the `receipt` type,
and the `failure` taxonomy. Network I/O requires PROP-035 in the following ways:

- **`affects external Network.RemoteEndpoint`** or **`affects external HTTP.ServerEndpoint`**:
  network operations reach external systems. The `affects external` clause
  (ch12 §12.3) is the mechanism by which this is declared at the contract
  header. Without PROP-035, this declaration has no compiler enforcement.

- **The `escape` modifier is required** (Covenant Postulate 4): every network
  call must be inside an `effect` or `irreversible` contract, not a `pure`
  contract. The E-NET-AMBIENT-BLOCKED error code enforces this; the underlying
  justification is Postulate 4 ("There is no I/O without a declaration").

- **Receipts per operation are required** (Postulate 8): every `send`, every
  `receive`, every `connect` and `listen` must produce a receipt. The `receipt`
  field in the Effect Surface (ch12 §12.3) is the declaration mechanism. The
  `SendReceipt` and `CloseReceipt` types sketched in §7.2 are the runtime
  evidence.

- **Failure taxonomy** (Postulate 15, ch12 §12.3) is critical for network IO.
  The distinction between `timed_out` (→ `UnknownExternalOutcome`) and `failed`
  (→ known error) is especially important for network operations. A connection
  timeout to a remote host leaves the connection state unknown: the request may
  or may not have been received. This maps to LAB-RACK-P1 §2.6's analysis of
  client disconnects (`EPIPE` → `unknown_external_state`).

- **`idempotency` declaration** (ch12 §12.3): a network `send` may or may not
  be idempotent depending on the protocol and application semantics. A
  `send_allowed` capability used in a retry-enabled profile must carry an
  `idempotency key` declaration or `idempotency none` to prevent silent
  duplicate operations.

This document is **upstream design pressure on PROP-035** — not a PROP itself.
The network capability schema provides concrete use cases for the Effect Surface
fields: the `affects external` clause needs `Network.RemoteEndpoint` and
`HTTP.ServerEndpoint` as named targets; the failure taxonomy needs
`UnknownExternalOutcome` for connection timeouts; the receipt schema needs
fields for network-specific metadata (`remote_host`, `remote_port`,
`bytes_sent`, `connection_id`). This evidence should inform the PROP-035
draft when its governance window opens, but this document does not author,
propose, or advance PROP-035.

---

## 10. Gap → Next Card Map

| Gap | Status | Required next card / PROP |
|---|---|---|
| Network capability schema (this document) | Research done (LAB-STDLIB-NET-P1) | LAB-STDLIB-NET-P2: Ruby proof runner validating schema + delegation algebra |
| Delegation algebra verification | Design complete (§4) | LAB-STDLIB-NET-P2: proof runner validates all 8 sub-grant conditions, all 7 violation classes, compose operator |
| Safety policy proof | Design complete (§3) | LAB-STDLIB-NET-P2: proof runner validates all 6 NET policies produce correct E-NET-* error codes |
| stdlib/io/network.ig interface | Design sketch only (§7) | LAB-STDLIB-NET-P3: FFI surface proof (Rust stub + Ruby runner) |
| Compiler network capability node classification | Not started | LAB-STDLIB-NET-P4: compiler E-NET-* diagnostic proofs |
| Passport schema extension | Design sketch (§6) | LAB-STDLIB-NET-P2: passport validation with mixed file + network grants |
| Service loop + network accept | Blocked (PROP-039+, Stage 4 deferred) | PROP-039+ (managed recursion) — not a lab card; requires formal governance |
| HTTP handler effect contract | Not started | Depends on PROP-035 + LAB-STDLIB-NET-P3; neither exists yet |
| `network.accept()` progression source | Not designed | Extends PROP-037 progression descriptors — see LAB-RACK-P1 §7 |

---

## 11. Non-Claims

This research does NOT claim:
- Network I/O is currently supported in Igniter Lang or igniter-lab.
- `IO.NetworkCapability` has a stable API shape. The schema in §2 is a
  research proposal, not an accepted schema.
- The proposed `stdlib/io/network.ig` exists in any form.
- The delegation algebra in §4 has been proof-verified. Verification is the
  work of LAB-STDLIB-NET-P2.
- PROP-035 Effect Surface enforcement applies to network I/O today. PROP-035
  has not been authored.
- This document proposes, authors, or advances any PROP.
- The `resource_type` registry in §6.2 is a canonical type registry.
- Any igniter-lang source files, spec chapters, or covenant text were modified
  as part of this research card.

---

## 12. Recommended Next Card

**LAB-STDLIB-NET-P2** — Network Capability Delegation Algebra Proof.

Follow the LAB-STDLIB-IO-P2 pattern exactly: write a Ruby proof runner that
validates the research claims from this document:

1. **Schema validation**: all three capability variants (Variant A: loopback
   connect, Variant B: localhost listen, Variant C: external HTTPS) parse and
   validate correctly.
2. **All seven delegation violations are rejected**: protocol escalation,
   permission escalation, loopback escape, host escape, port escape, TLS
   downgrade, bind escalation — each must produce the correct E-NET-DELEGATION-*
   error code.
3. **Sub-grant ordering relation verified for valid delegations**: a set of
   valid parent → child delegation pairs must all pass the 8-condition ⊑_net
   check.
4. **Compose operator produces correct intersection**: G₁ ∧ G₂ for several
   pairs must produce the expected composed grant.
5. **All six NET safety policies produce correct E-NET-* error codes**: one
   test case per policy (NET-1 through NET-6).
6. **Passport schema with mixed file + network grants validates correctly**: the
   extended passport from §6.1 must parse and validate, with the runtime
   applying file policies to `resource_type: "file"` grants and network policies
   to `resource_type: "network"` grants.

The proof runner must not implement any production network IO (no actual TCP
sockets). It validates the schema and algebra rules in memory, following the
established lab pattern.
