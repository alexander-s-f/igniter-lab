//! LAB-IGNITER-WEB-LIVE-BIND-DRY-RUN-VERDICT-P36 / P37
//!
//! Report-only live-bind dry run. Converts a parsed `[host.live_bind]` checklist
//! (P34) into the server-owned `LiveBindChecklist` and asks the **pure**
//! `authorize_bind` gate what it WOULD decide — **without ever opening a
//! listener**. This closes the next A10 tail while preserving the public-bind
//! HOLD decision (P35): the dry run never binds and grants no bind authority.
//!
//! P37 upgrades the signed-passport checklist bit from "path-shaped operator
//! assertion" to "host loaded and validated durable verifier material" for the
//! dry-run/check path. The current machine primitive is symmetric-key
//! `PassportVerifier`, so v0 accepts a narrow trusted-issuer key file: 64 hex
//! chars for one 32-byte issuer key. The key material is never printed, and the
//! dry run still opens no socket and grants no bind authority.
//!
//! Remaining authority boundary (P35): real `Run` still calls `authorize_bind`
//! with no checklist, TLS transport is P38, and the human-gated real flip is
//! P39. No real bind path consumes this conversion.

use crate::host_config::{LiveBindConfig, LiveBindTlsConfig};
use igniter_machine::capability::{
    sign_passport, verify_passport_signed, CapabilityPassport, PassportVerifier,
};
use igniter_machine::clock::{ClockProvider, SystemClock};
use igniter_server::serving_gate::{
    authorize_bind, InboundTlsMode, LiveBindChecklist, OperatorSignoff,
};
use std::net::SocketAddr;
use std::sync::Arc;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LiveBindVerifierLoadError {
    Unavailable,
    InvalidMaterial,
}

impl LiveBindVerifierLoadError {
    pub fn code(&self) -> &'static str {
        match self {
            Self::Unavailable => "signed_passport_verifier_unavailable",
            Self::InvalidMaterial => "signed_passport_verifier_invalid",
        }
    }
}

impl std::fmt::Display for LiveBindVerifierLoadError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.code())
    }
}

impl std::error::Error for LiveBindVerifierLoadError {}

fn parse_trusted_issuer_key(material: &str) -> Result<[u8; 32], LiveBindVerifierLoadError> {
    let hex = material.trim();
    if hex.len() != 64 || !hex.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err(LiveBindVerifierLoadError::InvalidMaterial);
    }
    let mut key = [0u8; 32];
    for i in 0..32 {
        key[i] = u8::from_str_radix(&hex[i * 2..i * 2 + 2], 16)
            .map_err(|_| LiveBindVerifierLoadError::InvalidMaterial)?;
    }
    Ok(key)
}

fn validates_probe_passport(verifier: &PassportVerifier, key: &[u8; 32]) -> bool {
    let mut passport = CapabilityPassport {
        subject: "live-bind-check".to_string(),
        capability_id: "igniter.live_bind.inbound".to_string(),
        scopes: vec!["inbound".to_string()],
        issued_at: 0.0,
        expires_at: None,
        revoked: false,
        evidence_digest: String::new(),
    };
    passport.evidence_digest = sign_passport(key, &passport);
    let clock: Arc<dyn ClockProvider> = Arc::new(SystemClock);
    verify_passport_signed(
        verifier,
        &passport,
        "igniter.live_bind.inbound",
        "inbound",
        &clock,
    )
    .is_ok()
}

/// Load the durable inbound passport verifier material referenced by
/// `[host.live_bind].signed_passport_path`.
///
/// v0 format is deliberately narrow because the current machine verifier is
/// symmetric-key only: a file containing one 64-hex-char 32-byte trusted issuer
/// key, optionally surrounded by whitespace. This function never returns or
/// logs the key material.
pub fn load_inbound_passport_verifier(
    signed_passport_path: &str,
) -> Result<PassportVerifier, LiveBindVerifierLoadError> {
    let material = std::fs::read_to_string(signed_passport_path)
        .map_err(|_| LiveBindVerifierLoadError::Unavailable)?;
    let key = parse_trusted_issuer_key(&material)?;
    let verifier = PassportVerifier::new().trust(key);
    if !validates_probe_passport(&verifier, &key) {
        return Err(LiveBindVerifierLoadError::InvalidMaterial);
    }
    Ok(verifier)
}

/// Convert the parsed, fail-closed `[host.live_bind]` config into the server
/// gate's `LiveBindChecklist`.
///
/// P34 parsing already forces every boolean assertion to `"true"` and every
/// reference / signoff to a non-empty, template-free string. P37 additionally
/// loads and validates the signed-passport verifier material before setting
/// `signed_passport_path_wired=true`.
pub fn config_to_checklist(
    cfg: &LiveBindConfig,
) -> Result<LiveBindChecklist, LiveBindVerifierLoadError> {
    let _verifier = load_inbound_passport_verifier(&cfg.signed_passport_path)?;
    Ok(LiveBindChecklist {
        signed_passport_path_wired: true,
        body_cap_enabled: cfg.body_cap_enabled,
        read_timeout_enabled: cfg.read_timeout_enabled,
        fail_closed_auth_enabled: cfg.fail_closed_auth_enabled,
        inbound_tls_mode: Some(match cfg.inbound_tls {
            LiveBindTlsConfig::TerminatedUpstream { .. } => InboundTlsMode::TerminatedUpstream,
            LiveBindTlsConfig::NativeTls { .. } => InboundTlsMode::NativeTls,
        }),
        operator_signoff: if cfg.operator_signoff.trim().is_empty() {
            OperatorSignoff::Missing
        } else {
            OperatorSignoff::Present
        },
    })
}

/// The report-only result of a live-bind dry run. Carries **no** bind authority.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LiveBindVerdict {
    /// Loopback: the gate authorizes with no checklist (`Ok(None)`). No public
    /// exposure; loopback serving is already allowed.
    WouldAuthorizeLoopback,
    /// Non-loopback with a complete, host-verified checklist: the gate WOULD issue
    /// a token. This is reported only — the dry run still does not bind, and a real
    /// non-loopback bind additionally requires P38/P39.
    WouldAuthorizeNonLoopback { checklist_digest: String },
    /// The gate would refuse. `code` is the stable refusal code; `missing_field`
    /// names the gap when there is a single one.
    WouldRefuse {
        code: String,
        missing_field: Option<String>,
    },
}

impl LiveBindVerdict {
    /// True when the gate would authorize (loopback no-op or non-loopback token).
    /// Even `true` grants NO bind authority in the dry run.
    pub fn would_authorize(&self) -> bool {
        !matches!(self, LiveBindVerdict::WouldRefuse { .. })
    }

    /// Stable, secret-free, single-line operator report. Never prints field
    /// values or file paths; the `checklist_digest` is proven field-value-free by
    /// the server gate. Always states `socket_opened=false public_bind=closed`.
    pub fn render(&self, addr: SocketAddr) -> String {
        let class = if addr.ip().is_loopback() {
            "loopback"
        } else {
            "non_loopback"
        };
        match self {
            LiveBindVerdict::WouldAuthorizeLoopback => format!(
                "[LIVE_BIND_DRY_RUN] addr={addr} class={class} verdict=would_authorize \
                 reason=loopback_no_checklist_required socket_opened=false public_bind=closed"
            ),
            LiveBindVerdict::WouldAuthorizeNonLoopback { checklist_digest } => format!(
                "[LIVE_BIND_DRY_RUN] addr={addr} class={class} verdict=would_authorize \
                 checklist_digest={checklist_digest} socket_opened=false public_bind=closed \
                 note=report_only_no_bind_authority"
            ),
            LiveBindVerdict::WouldRefuse {
                code,
                missing_field,
            } => {
                let mf = missing_field.as_deref().unwrap_or("-");
                format!(
                    "[LIVE_BIND_DRY_RUN] addr={addr} class={class} verdict=would_refuse \
                     code={code} missing_field={mf} socket_opened=false public_bind=closed"
                )
            }
        }
    }
}

/// Evaluate what `authorize_bind` WOULD return for `addr` given the parsed
/// live-bind config. Opens no sockets. For non-loopback checklist evaluation it
/// loads the durable signed-passport verifier material so
/// `signed_passport_path_wired` is host-verified. `None` config means there was
/// no `[host.live_bind]` section.
pub fn evaluate(addr: SocketAddr, live_bind: Option<&LiveBindConfig>) -> LiveBindVerdict {
    if addr.ip().is_loopback() {
        return match authorize_bind(addr, None) {
            Ok(None) => LiveBindVerdict::WouldAuthorizeLoopback,
            Ok(Some(token)) => LiveBindVerdict::WouldAuthorizeNonLoopback {
                checklist_digest: token.checklist_digest().to_string(),
            },
            Err(refusal) => LiveBindVerdict::WouldRefuse {
                code: refusal.code().to_string(),
                missing_field: refusal.missing_field().map(|s| s.to_string()),
            },
        };
    }
    let checklist = match live_bind {
        Some(cfg) => match config_to_checklist(cfg) {
            Ok(checklist) => Some(checklist),
            Err(e) => {
                return LiveBindVerdict::WouldRefuse {
                    code: e.code().to_string(),
                    missing_field: Some("signed_passport_path".to_string()),
                }
            }
        },
        None => None,
    };
    match authorize_bind(addr, checklist.as_ref()) {
        Ok(None) => LiveBindVerdict::WouldAuthorizeLoopback,
        Ok(Some(token)) => LiveBindVerdict::WouldAuthorizeNonLoopback {
            checklist_digest: token.checklist_digest().to_string(),
        },
        Err(refusal) => LiveBindVerdict::WouldRefuse {
            code: refusal.code().to_string(),
            missing_field: refusal.missing_field().map(|s| s.to_string()),
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

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

    fn write_verifier_material(tag: &str, material: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "igweb_p37_{tag}_{}_{}",
            std::process::id(),
            stamp()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("trusted_issuer.key");
        std::fs::write(&path, material).unwrap();
        path
    }

    fn valid_verifier_path(tag: &str) -> PathBuf {
        write_verifier_material(tag, &format!("{}\n", key_hex(0x11)))
    }

    fn complete_config() -> LiveBindConfig {
        LiveBindConfig {
            signed_passport_path: valid_verifier_path("complete")
                .to_string_lossy()
                .to_string(),
            body_cap_enabled: true,
            read_timeout_enabled: true,
            fail_closed_auth_enabled: true,
            operator_signoff: "present".to_string(),
            inbound_tls: LiveBindTlsConfig::TerminatedUpstream {
                upstream_header_policy: "x-forwarded-proto".to_string(),
            },
        }
    }

    fn loopback() -> SocketAddr {
        "127.0.0.1:8080".parse().unwrap()
    }
    fn non_loopback() -> SocketAddr {
        "0.0.0.0:8080".parse().unwrap()
    }

    #[test]
    fn complete_config_maps_to_complete_checklist() {
        let cl = config_to_checklist(&complete_config()).unwrap();
        assert!(cl.signed_passport_path_wired);
        assert!(cl.body_cap_enabled);
        assert!(cl.read_timeout_enabled);
        assert!(cl.fail_closed_auth_enabled);
        assert_eq!(
            cl.inbound_tls_mode,
            Some(InboundTlsMode::TerminatedUpstream)
        );
        assert_eq!(cl.operator_signoff, OperatorSignoff::Present);
    }

    #[test]
    fn native_tls_maps_to_native_tls_mode() {
        let mut cfg = complete_config();
        cfg.inbound_tls = LiveBindTlsConfig::NativeTls {
            cert_file: "/etc/tls/cert.pem".to_string(),
            key_file: "/etc/tls/key.pem".to_string(),
        };
        let cl = config_to_checklist(&cfg).unwrap();
        assert_eq!(cl.inbound_tls_mode, Some(InboundTlsMode::NativeTls));
    }

    #[test]
    fn missing_verifier_material_refuses_signed_passport_bit() {
        let mut cfg = complete_config();
        cfg.signed_passport_path = std::env::temp_dir()
            .join(format!(
                "igweb_p37_missing_{}_{}",
                std::process::id(),
                stamp()
            ))
            .to_string_lossy()
            .to_string();
        let err = config_to_checklist(&cfg).unwrap_err();
        assert_eq!(err, LiveBindVerifierLoadError::Unavailable);
        let v = evaluate(non_loopback(), Some(&cfg));
        assert_eq!(
            v,
            LiveBindVerdict::WouldRefuse {
                code: "signed_passport_verifier_unavailable".to_string(),
                missing_field: Some("signed_passport_path".to_string()),
            }
        );
    }

    #[test]
    fn malformed_verifier_material_refuses_signed_passport_bit() {
        let mut cfg = complete_config();
        cfg.signed_passport_path = write_verifier_material("malformed", "not-a-32-byte-key")
            .to_string_lossy()
            .to_string();
        let err = config_to_checklist(&cfg).unwrap_err();
        assert_eq!(err, LiveBindVerifierLoadError::InvalidMaterial);
        let v = evaluate(non_loopback(), Some(&cfg));
        assert_eq!(
            v,
            LiveBindVerdict::WouldRefuse {
                code: "signed_passport_verifier_invalid".to_string(),
                missing_field: Some("signed_passport_path".to_string()),
            }
        );
    }

    #[test]
    fn loopback_would_authorize_with_no_checklist() {
        // Loopback is allowed; a missing checklist is fine.
        assert_eq!(
            evaluate(loopback(), None),
            LiveBindVerdict::WouldAuthorizeLoopback
        );
        // Even with a config, loopback short-circuits to the no-checklist path.
        assert_eq!(
            evaluate(loopback(), Some(&complete_config())),
            LiveBindVerdict::WouldAuthorizeLoopback
        );
    }

    #[test]
    fn non_loopback_complete_config_would_authorize_with_digest() {
        let v = evaluate(non_loopback(), Some(&complete_config()));
        match &v {
            LiveBindVerdict::WouldAuthorizeNonLoopback { checklist_digest } => {
                assert!(checklist_digest.starts_with("live-bind-v0:"));
                // The digest must never leak field values (server-gate invariant).
                assert!(!checklist_digest.contains("true"));
                assert!(!checklist_digest.contains("terminated_upstream"));
            }
            other => panic!("expected would_authorize non-loopback, got {other:?}"),
        }
        assert!(v.would_authorize());
    }

    #[test]
    fn non_loopback_without_section_would_refuse() {
        let v = evaluate(non_loopback(), None);
        assert_eq!(
            v,
            LiveBindVerdict::WouldRefuse {
                code: "non_loopback_without_checklist".to_string(),
                missing_field: None,
            }
        );
        assert!(!v.would_authorize());
    }

    #[test]
    fn non_loopback_incomplete_checklist_names_missing_field() {
        // A checklist with one gap (e.g. signoff absent) reports that field. This
        // exercises the per-field refusal path even though P34 parsing cannot
        // currently produce a partial config — it keeps the verdict honest if the
        // config shape ever loosens.
        let mut cfg = complete_config();
        cfg.operator_signoff = "  ".to_string(); // whitespace → Missing
        let v = evaluate(non_loopback(), Some(&cfg));
        assert_eq!(
            v,
            LiveBindVerdict::WouldRefuse {
                code: "missing_operator_signoff".to_string(),
                missing_field: Some("operator_signoff".to_string()),
            }
        );
    }

    #[test]
    fn render_is_secret_free_and_marks_no_socket() {
        let cfg = complete_config();
        for v in [
            evaluate(loopback(), None),
            evaluate(non_loopback(), Some(&cfg)),
            evaluate(non_loopback(), None),
        ] {
            let line = v.render(non_loopback());
            assert!(line.contains("socket_opened=false"));
            assert!(line.contains("public_bind=closed"));
            // Never leak the passport path or signoff value.
            assert!(!line.contains("trusted_issuer.key"));
            assert!(!line.contains(&key_hex(0x11)));
            assert!(!line.contains("present"));
        }
    }
}
