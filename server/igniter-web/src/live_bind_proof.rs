//! LAB-IGNITER-WEB-LIVE-BIND-HUMAN-GATED-PROOF-P39
//!
//! Human-gated lab proof for the live-bind authority chain. This module reuses
//! the P37 host-verified checklist conversion, requires the P38
//! `terminated_upstream` posture, asks the pure server gate for a token, and
//! opens no listener. Normal `igweb-serve run` remains closed for non-loopback
//! binds.

use crate::host_config::{LiveBindConfig, LiveBindTlsConfig};
use crate::live_bind_check::config_to_checklist;
use igniter_server::serving_gate::{authorize_bind, classify_bind, BindClass};
use std::net::SocketAddr;

pub const LIVE_BIND_PROOF_ACK_ENV: &str = "IGNITER_LIVE_BIND_HUMAN_ACK";
pub const LIVE_BIND_PROOF_ACK_VALUE: &str = "I_UNDERSTAND_IGNITER_LAB_LIVE_BIND_P39";

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LiveBindProofVerdict {
    WouldAuthorize {
        checklist_digest: String,
    },
    WouldRefuse {
        code: String,
        missing_field: Option<String>,
    },
}

impl LiveBindProofVerdict {
    pub fn would_authorize(&self) -> bool {
        matches!(self, Self::WouldAuthorize { .. })
    }

    pub fn render(&self, addr: SocketAddr) -> String {
        let class = match classify_bind(addr) {
            BindClass::Loopback => "loopback",
            BindClass::NonLoopback => "non_loopback",
        };
        match self {
            Self::WouldAuthorize { checklist_digest } => format!(
                "[LIVE_BIND_PROOF] addr={addr} class={class} verdict=would_authorize \
                 checklist_digest={checklist_digest} human_ack=present \
                 tls=terminated_upstream upstream_header_policy=trusted_proxy_only \
                 bind_attempted=false socket_opened=false public_bind=closed \
                 note=lab_only_authorization_proof_no_listener"
            ),
            Self::WouldRefuse {
                code,
                missing_field,
            } => {
                let mf = missing_field.as_deref().unwrap_or("-");
                format!(
                    "[LIVE_BIND_PROOF] addr={addr} class={class} verdict=would_refuse \
                     code={code} missing_field={mf} bind_attempted=false \
                     socket_opened=false public_bind=closed"
                )
            }
        }
    }
}

pub fn evaluate(
    addr: SocketAddr,
    live_bind: Option<&LiveBindConfig>,
    human_ack: Option<&str>,
) -> LiveBindProofVerdict {
    if human_ack != Some(LIVE_BIND_PROOF_ACK_VALUE) {
        return refusal(
            "human_ack_missing_or_invalid",
            Some(LIVE_BIND_PROOF_ACK_ENV),
        );
    }
    if classify_bind(addr) == BindClass::Loopback {
        return refusal("loopback_not_live_bind_proof", Some("addr"));
    }
    let cfg = match live_bind {
        Some(cfg) => cfg,
        None => return refusal("non_loopback_without_checklist", None),
    };
    match &cfg.inbound_tls {
        LiveBindTlsConfig::TerminatedUpstream {
            upstream_header_policy,
        } if upstream_header_policy == "trusted_proxy_only" => {}
        LiveBindTlsConfig::TerminatedUpstream { .. } => {
            return refusal(
                "unsupported_upstream_header_policy",
                Some("upstream_header_policy"),
            )
        }
        LiveBindTlsConfig::NativeTls { .. } => {
            return refusal(
                "native_tls_transport_not_implemented",
                Some("inbound_tls.mode"),
            )
        }
    }
    let checklist = match config_to_checklist(cfg) {
        Ok(checklist) => checklist,
        Err(e) => return refusal(e.code(), Some("signed_passport_path")),
    };
    match authorize_bind(addr, Some(&checklist)) {
        Ok(Some(token)) => LiveBindProofVerdict::WouldAuthorize {
            checklist_digest: token.checklist_digest().to_string(),
        },
        Ok(None) => refusal("loopback_not_live_bind_proof", Some("addr")),
        Err(e) => refusal(e.code(), e.missing_field()),
    }
}

fn refusal(code: &str, missing_field: Option<&str>) -> LiveBindProofVerdict {
    LiveBindProofVerdict::WouldRefuse {
        code: code.to_string(),
        missing_field: missing_field.map(|s| s.to_string()),
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
            "igweb_p39_{tag}_{}_{}",
            std::process::id(),
            stamp()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("trusted_issuer.key");
        std::fs::write(&path, material).unwrap();
        path
    }

    fn complete_config() -> LiveBindConfig {
        LiveBindConfig {
            signed_passport_path: write_verifier_material("valid", &format!("{}\n", key_hex(0x39)))
                .to_string_lossy()
                .to_string(),
            body_cap_enabled: true,
            read_timeout_enabled: true,
            fail_closed_auth_enabled: true,
            operator_signoff: "present".to_string(),
            inbound_tls: LiveBindTlsConfig::TerminatedUpstream {
                upstream_header_policy: "trusted_proxy_only".to_string(),
            },
        }
    }

    fn non_loopback() -> SocketAddr {
        "0.0.0.0:8080".parse().unwrap()
    }

    #[test]
    fn missing_ack_refuses_before_authorization() {
        let cfg = complete_config();
        let v = evaluate(non_loopback(), Some(&cfg), None);
        assert_eq!(
            v,
            LiveBindProofVerdict::WouldRefuse {
                code: "human_ack_missing_or_invalid".to_string(),
                missing_field: Some(LIVE_BIND_PROOF_ACK_ENV.to_string()),
            }
        );
    }

    #[test]
    fn valid_ack_and_complete_terminated_upstream_authorizes_without_listener() {
        let cfg = complete_config();
        let v = evaluate(non_loopback(), Some(&cfg), Some(LIVE_BIND_PROOF_ACK_VALUE));
        match v {
            LiveBindProofVerdict::WouldAuthorize { checklist_digest } => {
                assert!(checklist_digest.starts_with("live-bind-v0:"));
            }
            other => panic!("expected authorization, got {other:?}"),
        }
    }

    #[test]
    fn loopback_is_not_a_live_bind_proof() {
        let cfg = complete_config();
        let v = evaluate(
            "127.0.0.1:8080".parse().unwrap(),
            Some(&cfg),
            Some(LIVE_BIND_PROOF_ACK_VALUE),
        );
        assert_eq!(
            v,
            LiveBindProofVerdict::WouldRefuse {
                code: "loopback_not_live_bind_proof".to_string(),
                missing_field: Some("addr".to_string()),
            }
        );
    }

    #[test]
    fn native_tls_refuses_for_lab_proof() {
        let mut cfg = complete_config();
        cfg.inbound_tls = LiveBindTlsConfig::NativeTls {
            cert_file: "/etc/tls/cert.pem".to_string(),
            key_file: "/etc/tls/key.pem".to_string(),
        };
        let v = evaluate(non_loopback(), Some(&cfg), Some(LIVE_BIND_PROOF_ACK_VALUE));
        assert_eq!(
            v,
            LiveBindProofVerdict::WouldRefuse {
                code: "native_tls_transport_not_implemented".to_string(),
                missing_field: Some("inbound_tls.mode".to_string()),
            }
        );
    }

    #[test]
    fn unsupported_header_policy_refuses_for_lab_proof() {
        let mut cfg = complete_config();
        cfg.inbound_tls = LiveBindTlsConfig::TerminatedUpstream {
            upstream_header_policy: "accept_client_headers".to_string(),
        };
        let v = evaluate(non_loopback(), Some(&cfg), Some(LIVE_BIND_PROOF_ACK_VALUE));
        assert_eq!(
            v,
            LiveBindProofVerdict::WouldRefuse {
                code: "unsupported_upstream_header_policy".to_string(),
                missing_field: Some("upstream_header_policy".to_string()),
            }
        );
    }

    #[test]
    fn missing_verifier_refuses_for_lab_proof() {
        let mut cfg = complete_config();
        cfg.signed_passport_path = std::env::temp_dir()
            .join(format!(
                "igweb_p39_missing_{}_{}",
                std::process::id(),
                stamp()
            ))
            .to_string_lossy()
            .to_string();
        let v = evaluate(non_loopback(), Some(&cfg), Some(LIVE_BIND_PROOF_ACK_VALUE));
        assert_eq!(
            v,
            LiveBindProofVerdict::WouldRefuse {
                code: "signed_passport_verifier_unavailable".to_string(),
                missing_field: Some("signed_passport_path".to_string()),
            }
        );
    }
}
