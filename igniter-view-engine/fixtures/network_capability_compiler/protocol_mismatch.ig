-- Illustrative only — not canon syntax
-- Card: LAB-STDLIB-NET-P4
-- Fixture: protocol_mismatch
-- Scenario: UDP operation on TCP-only capability — E-NET-PROTOCOL-MISMATCH
-- Expected diagnostic: E-NET-PROTOCOL-MISMATCH

contract ProtocolMismatch {
  capability net_tcp: IO.NetworkCapability { loopback_only: false, connect_allowed: true, listen_allowed: false, protocol: "tcp", allowed_hosts: "*", port_lo: 1, port_hi: 65535, tls_required: false }
  effect send_data using net_tcp

  fn send_udp_on_tcp_cap() -> Result[Unit, Error] {
    stdlib.io.network.connect(host: "127.0.0.1", port: 5000, cap: net_tcp, protocol: "udp")
  }
}
