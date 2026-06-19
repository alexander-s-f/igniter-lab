-- Illustrative only — not canon syntax
-- Card: LAB-STDLIB-NET-P4
-- Fixture: host_blocked
-- Scenario: Target host not in allowed_hosts — E-NET-HOST-BLOCKED
-- Expected diagnostic: E-NET-HOST-BLOCKED

contract HostBlocked {
  capability net_out: IO.NetworkCapability { loopback_only: false, connect_allowed: true, listen_allowed: false, protocol: "tcp", allowed_hosts: "trusted.example.com", port_lo: 443, port_hi: 443, tls_required: false }
  effect connect_to_trusted using net_out

  fn connect_to_untrusted() -> Result[Unit, Error] {
    stdlib.io.network.connect(host: "evil.attacker.com", port: 443, cap: net_out)
  }
}
