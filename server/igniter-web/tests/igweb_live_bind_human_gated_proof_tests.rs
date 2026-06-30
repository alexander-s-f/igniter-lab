//! LAB-IGNITER-WEB-LIVE-BIND-HUMAN-GATED-PROOF-P39
//!
//! Subprocess tests for `igweb-serve live-bind-proof`. The command proves the
//! P36/P37/P38 authority chain behind an explicit human acknowledgement, but it
//! opens no listener and grants no production bind authority.

use igniter_web::live_bind_proof::{LIVE_BIND_PROOF_ACK_ENV, LIVE_BIND_PROOF_ACK_VALUE};
use std::process::Command;

const BIN: &str = env!("CARGO_BIN_EXE_igweb-serve");

fn stamp() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos()
}

fn key_hex(seed: u8) -> String {
    (0..32)
        .map(|i| format!("{:02x}", seed.wrapping_add(i)))
        .collect::<Vec<_>>()
        .join("")
}

fn write_verifier_material(tag: &str, material: &str) -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!(
        "igweb_p39_{tag}_{}_{}",
        std::process::id(),
        stamp()
    ));
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("trusted_issuer.key");
    std::fs::write(&path, material).unwrap();
    path
}

fn write_host_toml(tag: &str, toml: &str) -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!(
        "igweb_p39_host_{tag}_{}_{}",
        std::process::id(),
        stamp()
    ));
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("host.toml");
    std::fs::write(&path, toml).unwrap();
    path
}

fn complete_config() -> (std::path::PathBuf, String) {
    let verifier = write_verifier_material("valid", &format!("{}\n", key_hex(0x39)));
    let toml = format!(
        "[host]\nmode = \"loopback\"\n\
[host.live_bind]\n\
signed_passport_path = \"{}\"\n\
body_cap_enabled = \"true\"\n\
read_timeout_enabled = \"true\"\n\
fail_closed_auth_enabled = \"true\"\n\
operator_signoff = \"present\"\n\
[host.live_bind.inbound_tls]\n\
mode = \"terminated_upstream\"\n\
upstream_header_policy = \"trusted_proxy_only\"\n",
        verifier.display()
    );
    (verifier, toml)
}

fn native_tls_config() -> (std::path::PathBuf, String) {
    let verifier = write_verifier_material("native", &format!("{}\n", key_hex(0x40)));
    let toml = format!(
        "[host]\nmode = \"loopback\"\n\
[host.live_bind]\n\
signed_passport_path = \"{}\"\n\
body_cap_enabled = \"true\"\n\
read_timeout_enabled = \"true\"\n\
fail_closed_auth_enabled = \"true\"\n\
operator_signoff = \"present\"\n\
[host.live_bind.inbound_tls]\n\
mode = \"native_tls\"\n\
cert_file = \"/etc/tls/cert.pem\"\n\
key_file = \"/etc/tls/key.pem\"\n",
        verifier.display()
    );
    (verifier, toml)
}

struct Run {
    code: i32,
    stdout: String,
    stderr: String,
}

fn run(args: &[&str], ack: Option<&str>) -> Run {
    let mut cmd = Command::new(BIN);
    cmd.args(args);
    match ack {
        Some(value) => {
            cmd.env(LIVE_BIND_PROOF_ACK_ENV, value);
        }
        None => {
            cmd.env_remove(LIVE_BIND_PROOF_ACK_ENV);
        }
    }
    let out = cmd.output().expect("spawn igweb-serve");
    Run {
        code: out.status.code().unwrap_or(-1),
        stdout: String::from_utf8_lossy(&out.stdout).to_string(),
        stderr: String::from_utf8_lossy(&out.stderr).to_string(),
    }
}

fn assert_no_socket(r: &Run) {
    assert!(
        !r.stdout.contains("listening http"),
        "proof command must never open a listener; stdout={}",
        r.stdout
    );
    assert!(
        r.stdout.contains("socket_opened=false") || r.code == 2,
        "proof verdict must mark socket_opened=false unless config parse failed; stdout={} stderr={}",
        r.stdout,
        r.stderr
    );
    assert!(
        r.stdout.contains("bind_attempted=false") || r.code == 2,
        "proof verdict must mark bind_attempted=false unless config parse failed; stdout={} stderr={}",
        r.stdout,
        r.stderr
    );
}

#[test]
fn missing_human_ack_refuses_before_bind() {
    let (verifier, complete) = complete_config();
    let cfg = write_host_toml("missing_ack", &complete);
    let r = run(
        &[
            "live-bind-proof",
            "--host-config",
            cfg.to_str().unwrap(),
            "--addr",
            "0.0.0.0:8080",
        ],
        None,
    );
    assert_eq!(r.code, 5, "stdout={} stderr={}", r.stdout, r.stderr);
    assert!(r.stdout.contains("[LIVE_BIND_PROOF]"));
    assert!(r.stdout.contains("verdict=would_refuse"));
    assert!(r.stdout.contains("code=human_ack_missing_or_invalid"));
    assert!(r.stdout.contains(LIVE_BIND_PROOF_ACK_ENV));
    assert_no_socket(&r);
    assert!(!r.stdout.contains(&verifier.display().to_string()));
    assert!(!r.stderr.contains(&verifier.display().to_string()));
}

#[test]
fn complete_terminated_upstream_authorizes_without_listener() {
    let (verifier, complete) = complete_config();
    let cfg = write_host_toml("complete", &complete);
    let r = run(
        &[
            "live-bind-proof",
            "--host-config",
            cfg.to_str().unwrap(),
            "--addr",
            "0.0.0.0:8080",
        ],
        Some(LIVE_BIND_PROOF_ACK_VALUE),
    );
    assert_eq!(r.code, 0, "stdout={} stderr={}", r.stdout, r.stderr);
    assert!(r.stdout.contains("[LIVE_BIND_PROOF]"));
    assert!(r.stdout.contains("verdict=would_authorize"));
    assert!(r.stdout.contains("class=non_loopback"));
    assert!(r.stdout.contains("checklist_digest=live-bind-v0:"));
    assert!(r.stdout.contains("human_ack=present"));
    assert!(r.stdout.contains("tls=terminated_upstream"));
    assert!(r
        .stdout
        .contains("upstream_header_policy=trusted_proxy_only"));
    assert!(r.stdout.contains("public_bind=closed"));
    assert_no_socket(&r);
    assert!(!r.stdout.contains(&verifier.display().to_string()));
    assert!(!r.stderr.contains(&verifier.display().to_string()));
    assert!(!r.stdout.contains(&key_hex(0x39)));
    assert!(!r.stderr.contains(&key_hex(0x39)));
}

#[test]
fn native_tls_refuses_for_human_gated_proof() {
    let (_verifier, toml) = native_tls_config();
    let cfg = write_host_toml("native", &toml);
    let r = run(
        &[
            "live-bind-proof",
            "--host-config",
            cfg.to_str().unwrap(),
            "--addr",
            "0.0.0.0:8080",
        ],
        Some(LIVE_BIND_PROOF_ACK_VALUE),
    );
    assert_eq!(r.code, 5, "stdout={} stderr={}", r.stdout, r.stderr);
    assert!(r.stdout.contains("verdict=would_refuse"));
    assert!(r
        .stdout
        .contains("code=native_tls_transport_not_implemented"));
    assert!(r.stdout.contains("missing_field=inbound_tls.mode"));
    assert_no_socket(&r);
}

#[test]
fn missing_verifier_material_refuses_for_human_gated_proof() {
    let missing = std::env::temp_dir().join(format!(
        "igweb_p39_missing_{}_{}",
        std::process::id(),
        stamp()
    ));
    let toml = format!(
        "[host]\nmode = \"loopback\"\n\
[host.live_bind]\n\
signed_passport_path = \"{}\"\n\
body_cap_enabled = \"true\"\n\
read_timeout_enabled = \"true\"\n\
fail_closed_auth_enabled = \"true\"\n\
operator_signoff = \"present\"\n\
[host.live_bind.inbound_tls]\n\
mode = \"terminated_upstream\"\n\
upstream_header_policy = \"trusted_proxy_only\"\n",
        missing.display()
    );
    let cfg = write_host_toml("missing_verifier", &toml);
    let r = run(
        &[
            "live-bind-proof",
            "--host-config",
            cfg.to_str().unwrap(),
            "--addr",
            "0.0.0.0:8080",
        ],
        Some(LIVE_BIND_PROOF_ACK_VALUE),
    );
    assert_eq!(r.code, 5, "stdout={} stderr={}", r.stdout, r.stderr);
    assert!(r.stdout.contains("verdict=would_refuse"));
    assert!(r
        .stdout
        .contains("code=signed_passport_verifier_unavailable"));
    assert!(r.stdout.contains("missing_field=signed_passport_path"));
    assert_no_socket(&r);
    assert!(!r.stdout.contains(&missing.display().to_string()));
    assert!(!r.stderr.contains(&missing.display().to_string()));
}

#[test]
fn incomplete_checklist_fails_config_parse_before_proof_verdict() {
    let cfg = write_host_toml(
        "incomplete",
        "[host]\nmode = \"loopback\"\n[host.live_bind]\nbody_cap_enabled = \"true\"\n",
    );
    let r = run(
        &[
            "live-bind-proof",
            "--host-config",
            cfg.to_str().unwrap(),
            "--addr",
            "0.0.0.0:8080",
        ],
        Some(LIVE_BIND_PROOF_ACK_VALUE),
    );
    assert_eq!(r.code, 2, "stdout={} stderr={}", r.stdout, r.stderr);
    assert!(r.stderr.contains("[CONFIG_PARSE]"));
    assert!(!r.stdout.contains("[LIVE_BIND_PROOF]"));
    assert_no_socket(&r);
}
