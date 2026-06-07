-- Illustrative only — not canon syntax
-- Card: LAB-STDLIB-NET-P4
-- Fixture: effect_undeclared
-- Scenario: Capability declared but no effect...using binding — E-NET-EFFECT-UNDECLARED
-- Expected diagnostic: E-NET-EFFECT-UNDECLARED

contract EffectUndeclared {
  capability net_conn: IO.NetworkCapability { loopback_only: true, connect_allowed: true, listen_allowed: false, protocol: "tcp", allowed_hosts: "127.0.0.1", port_lo: 8000, port_hi: 9000, tls_required: false }

  fn perform_connect() -> Result[Unit, Error] {
    stdlib.io.network.connect(host: "127.0.0.1", port: 8080, cap: net_conn)
  }
}
