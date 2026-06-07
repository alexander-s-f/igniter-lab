-- Illustrative only — not canon syntax
-- Card: LAB-STDLIB-NET-P4
-- Fixture: cap_unknown
-- Scenario: Network call references undeclared capability name — E-NET-CAP-UNKNOWN
-- Expected diagnostic: E-NET-CAP-UNKNOWN

contract CapUnknown {
  capability net_conn: IO.NetworkCapability { loopback_only: true, connect_allowed: true, listen_allowed: false, protocol: "tcp", allowed_hosts: "127.0.0.1", port_lo: 8000, port_hi: 9000, tls_required: false }
  effect connect_to_service using net_conn

  fn perform_connect() -> Result[Unit, Error] {
    stdlib.io.network.connect(host: "127.0.0.1", port: 8080, cap: undeclared_cap)
  }
}
