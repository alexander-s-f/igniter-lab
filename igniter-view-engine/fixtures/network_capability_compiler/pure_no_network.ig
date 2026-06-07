-- Illustrative only — not canon syntax
-- Card: LAB-STDLIB-NET-P4
-- Fixture: pure_no_network
-- Scenario: Pure contract with no network calls — core classification, zero diagnostics

contract PureNoNetwork {
  fn add(a: Int, b: Int) -> Int {
    a + b
  }

  fn greet(name: String) -> String {
    "Hello, " + name
  }
}
