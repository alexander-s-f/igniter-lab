-- Illustrative only — not canon syntax
-- Card: LAB-STDLIB-NET-P4
-- Fixture: ambient_blocked
-- Scenario: Pure contract (no capability declaration) calls network — E-NET-AMBIENT-BLOCKED
-- Expected diagnostic: E-NET-AMBIENT-BLOCKED

contract AmbientBlocked {
  fn call_without_cap() -> Result[Unit, Error] {
    stdlib.io.network.connect(host: "127.0.0.1", port: 8080)
  }
}
