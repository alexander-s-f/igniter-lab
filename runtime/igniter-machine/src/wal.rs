//! Machine WAL: an append-only `len(u32 BE) | msgpack(Fact) | crc32(u32 BE)` log.
//!
//! LAB-MACHINE-WAL-FSYNC-NONSILENT-RECOVERY-P2 hardens two hygiene gaps the owner-split
//! packet (P1) named on this file:
//!
//!   * **Durability is now explicit.** Each `append` flushes the buffer and then (by default)
//!     `fsync`s the data file via `File::sync_data` (fdatasync). The policy is selectable with
//!     [`WalDurability`]. NON-CLAIM: like the `.mpk` store, this guarantees flush-to-OS and, on
//!     platforms whose `fsync` reaches the device, flush-to-disk — but real power-loss safety is
//!     NOT claimed here (e.g. macOS `fsync` does not flush the drive's own write cache; that needs
//!     `F_FULLFSYNC`). See the proof packet.
//!   * **Recovery is no longer silent.** [`WALWriter::replay_reported`] returns a [`WalReplay`]
//!     that distinguishes a benign torn tail (the last append was interrupted) from real
//!     mid-stream corruption (CRC mismatch or a CRC-valid record that fails to decode), with byte
//!     offsets. The boot-facing [`WALWriter::replay`] tolerates a torn tail (recovers the healthy
//!     prefix) but FAILS CLOSED with [`EngineError::Corruption`] on mid-stream corruption rather
//!     than silently dropping or skipping history.

use crate::errors::EngineError;
use crate::fact::Fact;
use parking_lot::Mutex;
use std::fs::{File, OpenOptions};
use std::io::{BufReader, BufWriter, Read, Write};
use std::path::{Path, PathBuf};

/// WAL persistence policy for each [`WALWriter::append`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WalDurability {
    /// Flush the buffered writer to the OS page cache only. Survives a process crash; does NOT
    /// survive power loss. Cheapest — intended for tests and throughput-only paths.
    Flush,
    /// Flush, then `fsync` (`File::sync_data`) the log before returning. Default for machine
    /// receipts. See the module non-claim about device-level power-loss safety.
    Sync,
}

/// How a single WAL record failed to replay. `offset` is the record's start byte in the log.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WalCorruption {
    pub offset: u64,
    pub kind: WalCorruptionKind,
    pub detail: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WalCorruptionKind {
    /// The stored CRC does not match the body. Framing past this point is untrustworthy, so the
    /// scan stops here.
    CrcMismatch,
    /// The CRC matched the body but the body did not decode into a `Fact`. Framing is intact, so
    /// the scan continues past this record.
    Deserialize,
}

/// Outcome of a non-silent WAL scan. (`Fact` is not `PartialEq`, so the whole report is not
/// comparable; assert on `facts.len()`, `truncated_tail`, and `corrupt` instead.)
#[derive(Debug, Default)]
pub struct WalReplay {
    /// Facts recovered, in log order.
    pub facts: Vec<Fact>,
    /// Convenience: `facts.len()`.
    pub recovered: usize,
    /// True when the log ended on a partial record (a length/body/crc field cut short, or a body
    /// claiming more bytes than the file holds) — the signature of an append interrupted by a
    /// crash. The healthy prefix is still recovered. Benign on its own.
    pub truncated_tail: bool,
    /// Mid-stream corruption found while scanning (NOT a torn tail). Non-empty means the log's
    /// integrity is in question.
    pub corrupt: Vec<WalCorruption>,
}

pub struct WALWriter {
    path: PathBuf,
    durability: WalDurability,
    writer: Mutex<BufWriter<File>>,
}

impl WALWriter {
    /// Open (or create) the WAL with the default durable policy ([`WalDurability::Sync`]).
    pub fn new(path: &Path) -> Result<Self, EngineError> {
        Self::with_durability(path, WalDurability::Sync)
    }

    /// Open (or create) the WAL with an explicit persistence policy.
    pub fn with_durability(path: &Path, durability: WalDurability) -> Result<Self, EngineError> {
        let file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(path)
            .map_err(|e| EngineError::IOError(e.to_string()))?;
        Ok(Self {
            path: path.to_path_buf(),
            durability,
            writer: Mutex::new(BufWriter::new(file)),
        })
    }

    /// The configured persistence policy.
    pub fn durability(&self) -> WalDurability {
        self.durability
    }

    pub fn append(&self, fact: &Fact) -> Result<(), EngineError> {
        let body =
            rmp_serde::to_vec(fact).map_err(|e| EngineError::SerializationError(e.to_string()))?;
        let len = body.len() as u32;
        let crc = crc32fast::hash(&body);

        let mut lock = self.writer.lock();
        lock.write_all(&len.to_be_bytes())
            .map_err(|e| EngineError::IOError(e.to_string()))?;
        lock.write_all(&body)
            .map_err(|e| EngineError::IOError(e.to_string()))?;
        lock.write_all(&crc.to_be_bytes())
            .map_err(|e| EngineError::IOError(e.to_string()))?;
        lock.flush()
            .map_err(|e| EngineError::IOError(e.to_string()))?;
        // Explicit durability: push the just-flushed bytes through to the data file. `sync_data`
        // (fdatasync) skips the metadata sync `sync_all` would do — the WAL only appends, so file
        // length is the only metadata that matters and the append already updated it.
        if self.durability == WalDurability::Sync {
            lock.get_ref()
                .sync_data()
                .map_err(|e| EngineError::IOError(e.to_string()))?;
        }

        Ok(())
    }

    /// Boot-facing replay. Recovers the healthy prefix; tolerates a torn tail (a crash mid-append);
    /// FAILS CLOSED with [`EngineError::Corruption`] on mid-stream corruption rather than silently
    /// dropping history. For inspection without failing, use [`Self::replay_reported`].
    pub fn replay(&self) -> Result<Vec<Fact>, EngineError> {
        let report = self.replay_reported()?;
        if !report.corrupt.is_empty() {
            let first = &report.corrupt[0];
            return Err(EngineError::Corruption(format!(
                "WAL {} has {} corrupt record(s); first at offset {} ({:?}: {})",
                self.path.display(),
                report.corrupt.len(),
                first.offset,
                first.kind,
                first.detail
            )));
        }
        Ok(report.facts)
    }

    /// Non-silent scan of the WAL. Never fails on record corruption — it reports it. Only genuine
    /// I/O faults (cannot open / read the file) return `Err`.
    pub fn replay_reported(&self) -> Result<WalReplay, EngineError> {
        let mut report = WalReplay::default();
        if !self.path.exists() {
            return Ok(report);
        }
        let file = File::open(&self.path).map_err(|e| EngineError::IOError(e.to_string()))?;
        let file_len = file
            .metadata()
            .map_err(|e| EngineError::IOError(e.to_string()))?
            .len();
        let mut reader = BufReader::new(file);
        let mut offset: u64 = 0;

        loop {
            let record_offset = offset;

            let mut len_buf = [0u8; 4];
            let n = read_up_to(&mut reader, &mut len_buf)?;
            if n == 0 {
                break; // clean EOF exactly at a record boundary
            }
            if n < 4 {
                report.truncated_tail = true; // torn length field
                break;
            }
            let body_len = u32::from_be_bytes(len_buf) as usize;
            offset += 4;

            // A body (plus its 4-byte CRC) that cannot fit in the remaining file is a torn tail.
            // Checked BEFORE allocating so a corrupt length field cannot trigger a huge alloc.
            let remaining = file_len.saturating_sub(offset);
            if (body_len as u64).saturating_add(4) > remaining {
                report.truncated_tail = true;
                break;
            }

            let mut body = vec![0u8; body_len];
            let bn = read_up_to(&mut reader, &mut body)?;
            if bn < body_len {
                report.truncated_tail = true; // torn body
                break;
            }
            offset += body_len as u64;

            let mut crc_buf = [0u8; 4];
            let cn = read_up_to(&mut reader, &mut crc_buf)?;
            if cn < 4 {
                report.truncated_tail = true; // torn crc field
                break;
            }
            offset += 4;

            if u32::from_be_bytes(crc_buf) != crc32fast::hash(&body) {
                // The body and/or length is corrupt: we can no longer trust where the next record
                // starts, so stop and report.
                report.corrupt.push(WalCorruption {
                    offset: record_offset,
                    kind: WalCorruptionKind::CrcMismatch,
                    detail: format!("crc mismatch over {body_len}-byte body"),
                });
                break;
            }

            match rmp_serde::from_slice::<Fact>(&body) {
                Ok(fact) => report.facts.push(fact),
                Err(e) => {
                    // CRC matched, so framing is intact: record the bad payload and keep scanning.
                    report.corrupt.push(WalCorruption {
                        offset: record_offset,
                        kind: WalCorruptionKind::Deserialize,
                        detail: e.to_string(),
                    });
                }
            }
        }

        report.recovered = report.facts.len();
        Ok(report)
    }
}

/// Read up to `buf.len()` bytes, returning how many were actually read before EOF. `0` means a
/// clean EOF (nothing left); a value `< buf.len()` means a short/torn read. Genuine I/O errors
/// propagate; `Interrupted` is retried.
fn read_up_to(reader: &mut impl Read, buf: &mut [u8]) -> Result<usize, EngineError> {
    let mut filled = 0;
    while filled < buf.len() {
        match reader.read(&mut buf[filled..]) {
            Ok(0) => break,
            Ok(n) => filled += n,
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(e) => return Err(EngineError::IOError(e.to_string())),
        }
    }
    Ok(filled)
}
