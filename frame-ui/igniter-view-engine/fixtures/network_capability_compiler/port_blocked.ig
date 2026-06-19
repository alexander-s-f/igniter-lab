-- Illustrative only — not canon syntax
-- Card: LAB-STDLIB-NET-P4
-- Fixture: port_blocked
-- Scenario: Target port outside allowed_port_ranges — E-NET-PORT-BLOCKED
-- Expected diagnostic: E-NET-PORT-BLOCKED

contract PortBlocked {
  capability net_out: IO.NetworkCapability { loopback_only: false, connect_allowed: true, listen_allowed: false, protocol: "tcp", allowed_hosts: "api.example.com", port_lo: 443, port_hi: 443, tls_required: false }
  effect connect_to_api using net_out

  fn connect_wrong_port() -> Result[Unit, Error] {
    stdlib.io.network.connect(host: "api.example.com", port: 8080, cap: net_out)
  }
}
