-- Illustrative only — not canon syntax
-- Card: LAB-STDLIB-NET-P4
-- Fixture: tls_required
-- Scenario: Plaintext connection (tls:false) on tls_required capability — E-NET-TLS-REQUIRED
-- Expected diagnostic: E-NET-TLS-REQUIRED

contract TLSRequired {
  capability net_secure: IO.NetworkCapability { loopback_only: false, connect_allowed: true, listen_allowed: false, protocol: "tcp", allowed_hosts: "api.example.com", port_lo: 443, port_hi: 443, tls_required: true }
  effect connect_secure using net_secure

  fn connect_plaintext() -> Result[Unit, Error] {
    stdlib.io.network.connect(host: "api.example.com", port: 443, cap: net_secure, tls: false)
  }
}
