//! Host clock capability (LAB-MACHINE-CAPABILITY-IO-CLOCK-P4).
//!
//! Time is a **host capability**, not a language primitive. A `ClockProvider` is injected at
//! the ServiceLoop boundary and is the *only* source of a receipt's `transaction_time`. The
//! contract body never sees a clock — `dispatch` (the VM path) takes no clock, so there is no
//! `now()` reachable from inside a contract. Tests inject a `FixedClock` for determinism;
//! production uses `SystemClock`. Replay never reads the clock (it does not write a receipt),
//! so a replayed effect never rewrites the original timestamp.

/// Source of a transaction-time stamp for receipts. Stamped ONLY at the ServiceLoop boundary.
pub trait ClockProvider: Send + Sync {
    /// The current transaction-time stamp (seconds since the Unix epoch for `SystemClock`;
    /// an explicit value for `FixedClock`).
    fn now(&self) -> f64;
}

/// Deterministic clock for tests — always returns the same stamp.
pub struct FixedClock {
    t: f64,
}

impl FixedClock {
    pub fn new(t: f64) -> Self {
        Self { t }
    }
}

impl ClockProvider for FixedClock {
    fn now(&self) -> f64 {
        self.t
    }
}

/// Real host wall-clock — the production boundary clock. This is the single place real time
/// enters the capability IO path.
#[derive(Default)]
pub struct SystemClock;

impl SystemClock {
    pub fn new() -> Self {
        Self
    }
}

impl ClockProvider for SystemClock {
    fn now(&self) -> f64 {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs_f64())
            .unwrap_or(0.0)
    }
}
