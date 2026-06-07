-- Illustrative only — not canon syntax
-- Card: LAB-STDLIB-NET-P4
-- Fixture: direction_blocked
-- Scenario: connect-only capability (listen_allowed:false) used for listen op — E-NET-DIRECTION-BLOCKED
-- Expected diagnostic: E-NET-DIRECTION-BLOCKED

contract DirectionBlocked {
  capability net_conn: IO.NetworkCapability { loopback_only: true, connect_allowed: true, listen_allowed: false, protocol: "tcp", allowed_hosts: "127.0.0.1", port_lo: 7000, port_hi: 8000, tls_required: false }
  effect accept_conn using net_conn

  fn start_listen() -> Result[Unit, Error] {
    stdlib.io.network.listen(host: "127.0.0.1", port: 7500, cap: net_conn)
  }
}
