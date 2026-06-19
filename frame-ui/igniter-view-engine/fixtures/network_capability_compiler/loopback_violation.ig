-- Illustrative only — not canon syntax
-- Card: LAB-STDLIB-NET-P4
-- Fixture: loopback_violation
-- Scenario: Non-loopback host used with loopback_only capability — E-NET-LOOPBACK-VIOLATION
-- allowed_hosts: "*" (wildcard) ensures host check passes; loopback_only check fires
-- Expected diagnostic: E-NET-LOOPBACK-VIOLATION

contract LoopbackViolation {
  capability net_local: IO.NetworkCapability { loopback_only: true, connect_allowed: true, listen_allowed: false, protocol: "tcp", allowed_hosts: "*", port_lo: 1, port_hi: 65535, tls_required: false }
  effect connect_local using net_local

  fn connect_external() -> Result[Unit, Error] {
    stdlib.io.network.connect(host: "external.example.com", port: 8080, cap: net_local)
  }
}
