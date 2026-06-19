// tests/igweb_lowering_tests.rs — LAB-IGNITER-WEB-ROUTING-LOWERING-P4
// Lower a `.igweb` Todo app to explicit `.ig`, then prove the generated project compiles through the
// real compiler (multifile compile_units, via the binary) with no OOF-RE1 / OOF-TY0 from the generated
// regexp / call_contract. The two static fixtures are inspectable; routes.ig is generated.

use igniter_compiler::igweb::{lower_igweb, PRELUDE_SOURCE};
use std::process::Command;

// P10: handlers import the shared `IgWebPrelude` (Request/Decision); no per-app `web_types.ig`.
const HANDLERS: &str = include_str!("fixtures/igweb_todo/handlers.ig");

const TODO_IGWEB: &str = "\
app TodoWeb entry Serve {
  handlers TodoHandlers
  route GET  \"/health\"          -> Health
  route GET  \"/todos\"           -> TodoIndex
  route POST \"/todos\"           -> TodoCreate requires idempotency
  route GET  \"/todos/:id\"       -> TodoShow
  route POST \"/todos/:id/done\"  -> TodoDone requires idempotency
}
";

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_igniter_compiler")
}

/// Write the three modules (two static fixtures + generated routes) to a unique temp dir and run the
/// real multifile compile. Returns the compiler's stdout (the result JSON text).
fn compile_generated(routes_ig: &str, tag: &str) -> String {
    let dir = std::env::temp_dir().join(format!("igweb_{}_{}", tag, std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let pl = dir.join("prelude.ig");
    let hd = dir.join("handlers.ig");
    let rt = dir.join("routes.ig");
    std::fs::write(&pl, PRELUDE_SOURCE).unwrap();
    std::fs::write(&hd, HANDLERS).unwrap();
    std::fs::write(&rt, routes_ig).unwrap();
    let out = dir.join("out.igapp");
    let output = Command::new(bin())
        .args([
            "compile",
            pl.to_str().unwrap(),
            hd.to_str().unwrap(),
            rt.to_str().unwrap(),
            "--out",
            out.to_str().unwrap(),
        ])
        .output()
        .expect("run igniter_compiler");
    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    assert!(
        output.status.success(),
        "generated project must compile successfully.\n--- routes.ig ---\n{}\n--- stdout ---\n{}\n--- stderr ---\n{}",
        routes_ig,
        stdout,
        stderr
    );
    assert!(out.exists(), "compiler should write the .igapp artifact at {}", out.display());
    stdout
}

#[test]
fn generated_todo_project_compiles_clean() {
    let routes = lower_igweb(TODO_IGWEB).expect("lower");
    // sanity: the generated artifact is the explicit, static, regexp-backed shape.
    assert!(routes.contains("pure contract Serve"));
    assert!(routes.contains("call_contract(\"TodoShow\", req, capture(req.path, \"^/todos/([^/]+)$\", 1))"));
    assert!(routes.contains("call_contract(\"TodoDone\", req, capture(req.path, \"^/todos/([^/]+)/done$\", 1))"));
    assert!(routes.contains("matches(req.path,"));
    assert!(!routes.contains("call_contract(req"), "no dynamic dispatch");

    let stdout = compile_generated(&routes, "todo");
    assert!(
        !stdout.contains("OOF-RE1"),
        "generated regexp must be valid (no OOF-RE1).\n--- routes.ig ---\n{}\n--- stdout ---\n{}",
        routes, stdout
    );
    assert!(
        !stdout.contains("OOF-TY0"),
        "generated call_contract/regexp must typecheck (no OOF-TY0).\n--- routes.ig ---\n{}\n--- stdout ---\n{}",
        routes, stdout
    );
}

#[test]
fn nested_middle_param_lowers_two_captures() {
    // /accounts/:account_id/todos/:id — the middle-param case split+nth could not express (P3 unlock).
    // Both params extract positionally via capture(index 1) + capture(index 2) — no split/nth tricks.
    let src = "app AccTodo entry Serve {\n  handlers AccHandlers\n  route GET \"/accounts/:account_id/todos/:id\" -> AccountTodoShow\n}\n";
    let routes = lower_igweb(src).expect("lower");
    assert!(routes.contains("matches(req.path, \"^/accounts/([^/]+)/todos/([^/]+)$\")"));
    assert!(routes.contains("capture(req.path, \"^/accounts/([^/]+)/todos/([^/]+)$\", 1)"));
    assert!(routes.contains("capture(req.path, \"^/accounts/([^/]+)/todos/([^/]+)$\", 2)"));
    assert!(routes.contains("call_contract(\"AccountTodoShow\", req, capture(req.path, \"^/accounts/([^/]+)/todos/([^/]+)$\", 1), capture(req.path, \"^/accounts/([^/]+)/todos/([^/]+)$\", 2))"));
}
