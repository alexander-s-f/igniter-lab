-- Illustrative only — not canon syntax
-- Card: LAB-STDLIB-NET-P4
-- Fixture: good_tls_outbound
-- Scenario: Valid TLS outbound contract — escape classification, zero diagnostics
-- Variant C from P1: external HTTPS connect (loopback_only:false, tls_required:true)

contract GoodTLSOutbound {
  capability net_out: IO.NetworkCapability { loopback_only: false, connect_allowed: true, listen_allowed: false, protocol: "tcp", allowed_hosts: "api.example.com", port_lo: 443, port_hi: 443, tls_required: true }
  effect connect_to_api using net_out

  fn call_api() -> Result[Unit, Error] {
    stdlib.io.network.connect(host: "api.example.com", port: 443, cap: net_out, tls: true, protocol: "tcp")
  }
}
