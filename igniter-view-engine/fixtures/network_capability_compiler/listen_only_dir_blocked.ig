-- Illustrative only — not canon syntax
-- Card: LAB-STDLIB-NET-P4
-- Fixture: listen_only_dir_blocked
-- Scenario: listen-only capability (connect_allowed:false) used for connect op — E-NET-DIRECTION-BLOCKED
-- Expected diagnostic: E-NET-DIRECTION-BLOCKED

contract ListenOnlyDirBlocked {
  capability net_listen: IO.NetworkCapability { loopback_only: true, connect_allowed: false, listen_allowed: true, protocol: "tcp", allowed_hosts: "127.0.0.1", port_lo: 7000, port_hi: 8000, tls_required: false }
  effect connect_op using net_listen

  fn do_connect() -> Result[Unit, Error] {
    stdlib.io.network.connect(host: "127.0.0.1", port: 7500, cap: net_listen)
  }
}
