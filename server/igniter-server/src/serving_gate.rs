//! Server-owned live bind gate.
//!
//! This module is intentionally pure: it opens no sockets and reads no host
//! config. Callers ask for a bind authorization before attempting a bind.

use std::error::Error;
use std::fmt;
use std::net::SocketAddr;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BindClass {
    Loopback,
    NonLoopback,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum InboundTlsMode {
    TerminatedUpstream,
    NativeTls,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum OperatorSignoff {
    Missing,
    Present,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LiveBindChecklist {
    pub signed_passport_path_wired: bool,
    pub body_cap_enabled: bool,
    pub read_timeout_enabled: bool,
    pub fail_closed_auth_enabled: bool,
    pub inbound_tls_mode: Option<InboundTlsMode>,
    pub operator_signoff: OperatorSignoff,
}

/// Opaque proof that a non-loopback bind passed the server-owned checklist.
///
/// External crates can inspect the sanitized metadata through accessors, but
/// cannot construct a token directly.
///
/// ```compile_fail
/// use igniter_server::serving_gate::{BindClass, LiveBindToken};
///
/// let _forged = LiveBindToken {
///     bind_addr: "0.0.0.0:8080".parse().unwrap(),
///     issued_for: BindClass::NonLoopback,
///     checklist_digest: String::new(),
/// };
/// ```
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LiveBindToken {
    bind_addr: SocketAddr,
    issued_for: BindClass,
    checklist_digest: String,
}

impl LiveBindToken {
    pub fn bind_addr(&self) -> SocketAddr {
        self.bind_addr
    }

    pub fn issued_for(&self) -> BindClass {
        self.issued_for
    }

    pub fn checklist_digest(&self) -> &str {
        &self.checklist_digest
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LiveBindRefusal {
    NonLoopbackWithoutChecklist,
    MissingSignedPassport,
    MissingBodyCap,
    MissingReadTimeout,
    MissingFailClosedAuth,
    MissingInboundTlsDecision,
    MissingOperatorSignoff,
}

impl LiveBindRefusal {
    pub fn code(self) -> &'static str {
        match self {
            Self::NonLoopbackWithoutChecklist => "non_loopback_without_checklist",
            Self::MissingSignedPassport => "missing_signed_passport",
            Self::MissingBodyCap => "missing_body_cap",
            Self::MissingReadTimeout => "missing_read_timeout",
            Self::MissingFailClosedAuth => "missing_fail_closed_auth",
            Self::MissingInboundTlsDecision => "missing_inbound_tls_decision",
            Self::MissingOperatorSignoff => "missing_operator_signoff",
        }
    }

    pub fn missing_field(self) -> Option<&'static str> {
        match self {
            Self::NonLoopbackWithoutChecklist => None,
            Self::MissingSignedPassport => Some("signed_passport_path_wired"),
            Self::MissingBodyCap => Some("body_cap_enabled"),
            Self::MissingReadTimeout => Some("read_timeout_enabled"),
            Self::MissingFailClosedAuth => Some("fail_closed_auth_enabled"),
            Self::MissingInboundTlsDecision => Some("inbound_tls_mode"),
            Self::MissingOperatorSignoff => Some("operator_signoff"),
        }
    }
}

impl fmt::Display for LiveBindRefusal {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self.missing_field() {
            Some(field) => write!(f, "{}: {}", self.code(), field),
            None => write!(f, "{}", self.code()),
        }
    }
}

impl Error for LiveBindRefusal {}

pub fn classify_bind(addr: SocketAddr) -> BindClass {
    if addr.ip().is_loopback() {
        BindClass::Loopback
    } else {
        BindClass::NonLoopback
    }
}

pub fn authorize_bind(
    addr: SocketAddr,
    checklist: Option<&LiveBindChecklist>,
) -> Result<Option<LiveBindToken>, LiveBindRefusal> {
    match classify_bind(addr) {
        BindClass::Loopback => Ok(None),
        BindClass::NonLoopback => {
            let checklist = checklist.ok_or(LiveBindRefusal::NonLoopbackWithoutChecklist)?;
            validate_checklist(checklist)?;
            Ok(Some(LiveBindToken {
                bind_addr: addr,
                issued_for: BindClass::NonLoopback,
                checklist_digest: checklist_digest(checklist),
            }))
        }
    }
}

fn validate_checklist(checklist: &LiveBindChecklist) -> Result<(), LiveBindRefusal> {
    if !checklist.signed_passport_path_wired {
        return Err(LiveBindRefusal::MissingSignedPassport);
    }
    if !checklist.body_cap_enabled {
        return Err(LiveBindRefusal::MissingBodyCap);
    }
    if !checklist.read_timeout_enabled {
        return Err(LiveBindRefusal::MissingReadTimeout);
    }
    if !checklist.fail_closed_auth_enabled {
        return Err(LiveBindRefusal::MissingFailClosedAuth);
    }
    if checklist.inbound_tls_mode.is_none() {
        return Err(LiveBindRefusal::MissingInboundTlsDecision);
    }
    if checklist.operator_signoff != OperatorSignoff::Present {
        return Err(LiveBindRefusal::MissingOperatorSignoff);
    }
    Ok(())
}

fn checklist_digest(checklist: &LiveBindChecklist) -> String {
    let tls = match checklist.inbound_tls_mode {
        Some(InboundTlsMode::TerminatedUpstream) => "terminated_upstream",
        Some(InboundTlsMode::NativeTls) => "native_tls",
        None => "missing",
    };
    let signoff = match checklist.operator_signoff {
        OperatorSignoff::Missing => "missing",
        OperatorSignoff::Present => "present",
    };
    let canonical = format!(
        "live-bind-v0|signed_passport_path_wired={}|body_cap_enabled={}|read_timeout_enabled={}|fail_closed_auth_enabled={}|inbound_tls_mode={}|operator_signoff={}",
        checklist.signed_passport_path_wired,
        checklist.body_cap_enabled,
        checklist.read_timeout_enabled,
        checklist.fail_closed_auth_enabled,
        tls,
        signoff
    );
    format!("live-bind-v0:{:016x}", fnv1a64(canonical.as_bytes()))
}

fn fnv1a64(bytes: &[u8]) -> u64 {
    let mut hash = 0xcbf29ce484222325u64;
    for byte in bytes {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

#[cfg(test)]
mod tests {
    use super::*;

    fn complete_checklist() -> LiveBindChecklist {
        LiveBindChecklist {
            signed_passport_path_wired: true,
            body_cap_enabled: true,
            read_timeout_enabled: true,
            fail_closed_auth_enabled: true,
            inbound_tls_mode: Some(InboundTlsMode::TerminatedUpstream),
            operator_signoff: OperatorSignoff::Present,
        }
    }

    #[test]
    fn classify_loopback_and_non_loopback_addrs() {
        assert_eq!(
            classify_bind("127.0.0.1:8080".parse().unwrap()),
            BindClass::Loopback
        );
        assert_eq!(
            classify_bind("[::1]:8080".parse().unwrap()),
            BindClass::Loopback
        );
        assert_eq!(
            classify_bind("0.0.0.0:8080".parse().unwrap()),
            BindClass::NonLoopback
        );
        assert_eq!(
            classify_bind("192.0.2.10:8080".parse().unwrap()),
            BindClass::NonLoopback
        );
    }

    #[test]
    fn loopback_authorization_needs_no_checklist() {
        let addr = "127.0.0.1:8080".parse().unwrap();
        assert_eq!(authorize_bind(addr, None).unwrap(), None);
    }

    #[test]
    fn non_loopback_without_checklist_is_refused() {
        let addr = "0.0.0.0:8080".parse().unwrap();
        let refusal = authorize_bind(addr, None).unwrap_err();
        assert_eq!(refusal, LiveBindRefusal::NonLoopbackWithoutChecklist);
        assert_eq!(refusal.code(), "non_loopback_without_checklist");
        assert_eq!(refusal.missing_field(), None);
    }

    #[test]
    fn non_loopback_reports_each_missing_checklist_field() {
        let addr = "192.0.2.10:8080".parse().unwrap();
        let mut checklist = complete_checklist();

        checklist.signed_passport_path_wired = false;
        assert_eq!(
            authorize_bind(addr, Some(&checklist)).unwrap_err(),
            LiveBindRefusal::MissingSignedPassport
        );
        checklist.signed_passport_path_wired = true;

        checklist.body_cap_enabled = false;
        assert_eq!(
            authorize_bind(addr, Some(&checklist)).unwrap_err(),
            LiveBindRefusal::MissingBodyCap
        );
        checklist.body_cap_enabled = true;

        checklist.read_timeout_enabled = false;
        assert_eq!(
            authorize_bind(addr, Some(&checklist)).unwrap_err(),
            LiveBindRefusal::MissingReadTimeout
        );
        checklist.read_timeout_enabled = true;

        checklist.fail_closed_auth_enabled = false;
        assert_eq!(
            authorize_bind(addr, Some(&checklist)).unwrap_err(),
            LiveBindRefusal::MissingFailClosedAuth
        );
        checklist.fail_closed_auth_enabled = true;

        checklist.inbound_tls_mode = None;
        assert_eq!(
            authorize_bind(addr, Some(&checklist)).unwrap_err(),
            LiveBindRefusal::MissingInboundTlsDecision
        );
        checklist.inbound_tls_mode = Some(InboundTlsMode::NativeTls);

        checklist.operator_signoff = OperatorSignoff::Missing;
        let refusal = authorize_bind(addr, Some(&checklist)).unwrap_err();
        assert_eq!(refusal, LiveBindRefusal::MissingOperatorSignoff);
        assert_eq!(
            refusal.to_string(),
            "missing_operator_signoff: operator_signoff"
        );
    }

    #[test]
    fn complete_non_loopback_checklist_returns_opaque_token() {
        let addr = "0.0.0.0:8080".parse().unwrap();
        let checklist = complete_checklist();
        let token = authorize_bind(addr, Some(&checklist)).unwrap().unwrap();
        assert_eq!(token.bind_addr(), addr);
        assert_eq!(token.issued_for(), BindClass::NonLoopback);
        assert!(token.checklist_digest().starts_with("live-bind-v0:"));
        assert!(!token.checklist_digest().contains("true"));
        assert!(!token.checklist_digest().contains("terminated_upstream"));
    }
}
