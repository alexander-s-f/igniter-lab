//! LAB-IGNITER-WEB-LIVE-BIND-DRY-RUN-VERDICT-P36
//!
//! Report-only live-bind dry run. Converts a parsed `[host.live_bind]` checklist
//! (P34) into the server-owned `LiveBindChecklist` and asks the **pure**
//! `authorize_bind` gate what it WOULD decide — **without ever opening a
//! listener**. This closes the next A10 tail while preserving the public-bind
//! HOLD decision (P35): the dry run never binds and grants no bind authority.
//!
//! Authority boundary (P35): in this slice the checklist booleans are a 1:1
//! readiness mapping from the operator's asserted config. That is sound ONLY
//! because the dry run never binds — it reports what the gate WOULD decide for
//! the *asserted* config. Host-verified backing (each boolean set from real
//! runtime state, not the operator's claim) is P37; durable inbound
//! signed-passport key is P37; TLS transport is P38; the human-gated real flip
//! is P39. No real bind path consumes this conversion.

use crate::host_config::{LiveBindConfig, LiveBindTlsConfig};
use igniter_server::serving_gate::{
    authorize_bind, InboundTlsMode, LiveBindChecklist, OperatorSignoff,
};
use std::net::SocketAddr;

/// Convert the parsed, fail-closed `[host.live_bind]` config into the server
/// gate's `LiveBindChecklist`.
///
/// P34 parsing already forces every boolean assertion to `"true"` and every file
/// reference / signoff to a non-empty, template-free string, so a successfully
/// parsed `LiveBindConfig` maps to a *complete* checklist. The emptiness guards
/// here are defensive — they keep the conversion honest if the config shape ever
/// loosens.
pub fn config_to_checklist(cfg: &LiveBindConfig) -> LiveBindChecklist {
    LiveBindChecklist {
        signed_passport_path_wired: !cfg.signed_passport_path.trim().is_empty(),
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
    }
}

/// The report-only result of a live-bind dry run. Carries **no** bind authority.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LiveBindVerdict {
    /// Loopback: the gate authorizes with no checklist (`Ok(None)`). No public
    /// exposure; loopback serving is already allowed.
    WouldAuthorizeLoopback,
    /// Non-loopback with a complete checklist: the gate WOULD issue a token. This
    /// is reported only — the dry run still does not bind, and a real
    /// non-loopback bind additionally requires P37/P38/P39.
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
/// live-bind config. **Pure**: opens no sockets, performs no I/O. `None` config
/// means there was no `[host.live_bind]` section.
pub fn evaluate(addr: SocketAddr, live_bind: Option<&LiveBindConfig>) -> LiveBindVerdict {
    let checklist = live_bind.map(config_to_checklist);
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

    fn complete_config() -> LiveBindConfig {
        LiveBindConfig {
            signed_passport_path: "/etc/igniter/inbound_passport.pub".to_string(),
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
        let cl = config_to_checklist(&complete_config());
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
        let cl = config_to_checklist(&cfg);
        assert_eq!(cl.inbound_tls_mode, Some(InboundTlsMode::NativeTls));
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
            assert!(!line.contains("inbound_passport.pub"));
            assert!(!line.contains("present"));
        }
    }
}
