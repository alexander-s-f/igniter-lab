-- Illustrative only — not canon syntax
-- Card: LAB-STDLIB-NET-P4
-- Fixture: good_listen
-- Scenario: Valid loopback listen contract — escape classification, zero diagnostics

contract GoodListen {
  capability net_listen: IO.NetworkCapability { loopback_only: true, connect_allowed: false, listen_allowed: true, protocol: "tcp", allowed_hosts: "127.0.0.1", port_lo: 7000, port_hi: 8000, tls_required: false }
  effect accept_connection using net_listen

  fn start_listener() -> Result[Unit, Error] {
    stdlib.io.network.listen(host: "127.0.0.1", port: 7500, cap: net_listen)
  }
}
