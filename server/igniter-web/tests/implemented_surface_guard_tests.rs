//! implemented_surface_guard_tests.rs — LAB-IGNITER-WEB-IMPLEMENTED-SURFACE-GUARD-P33
//!
//! Anti-rot guard for the package front door. Runs on every `cargo test` (no feature, no DB needed).
//!
//! It does NOT grade prose and never reads any historical/proof doc — so old "deferred / observed only"
//! prose can never make this fail. It only asserts that the P31 front door (`IMPLEMENTED_SURFACE.md`)
//! and the P33 guard script still exist and that the doc still names its STABLE anchors: actual code
//! identifiers / file names the surface is ABOUT, which cannot disappear without the doc going wrong.
//! Wording/phrasing changes do not affect it.

use std::path::PathBuf;

fn crate_file(rel: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(rel)
}

#[test]
fn front_door_exists_and_names_its_code_anchors() {
    let path = crate_file("IMPLEMENTED_SURFACE.md");
    let text = std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("IMPLEMENTED_SURFACE.md must exist (the P31 front door): {e}"));

    // Stable anchors: code identifiers / file names, not prose.
    for anchor in [
        "ReadThen",
        "dispatch_with_read",
        "read_continuation",
        "StagedReadHost",
        "DatasetMeta",
        "PROJECTION_SCHEMA_INVALID",
        "typed_html_tests",
        "MachineEffectHost",
        "RenderView",
        "link",
        "host_config",
        "host.example.toml",
        "todo_postgres_smoke.sh",
        "runner_diag",
        "check_implemented_surface.sh", // must point at the one-command guard
        "cargo test",                   // must keep citing runnable evidence
    ] {
        assert!(
            text.contains(anchor),
            "IMPLEMENTED_SURFACE.md must reference `{anchor}` — the front door has drifted from the \
             implemented surface; update the doc rather than deleting the anchor"
        );
    }
}

#[test]
fn guard_script_exists() {
    let script = crate_file("scripts/check_implemented_surface.sh");
    assert!(
        script.exists(),
        "scripts/check_implemented_surface.sh must exist (the P33 one-command surface guard)"
    );
}
