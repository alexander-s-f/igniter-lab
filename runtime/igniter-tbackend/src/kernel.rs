// src/kernel.rs
// TBackend Packet Profile and Kernel Modularization Core

use crate::pure_core::{FileBackend, ShardedFactLog};
use parking_lot::RwLock;
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64};
use std::sync::Arc;

// ── StoreEngine Domain Model ──────────────────────────────────────────────────

pub struct StoreEngine {
    pub log: Arc<ShardedFactLog>,
    pub wal: Option<Arc<FileBackend>>,
}

// ── Per-store compaction guard ───────────────────────────────────────────────
// LAB-TBACKEND-SAFE-COMPACTION-STOP-THE-WORLD-P12. The guard lives in the kernel,
// keyed by store name, so it is STABLE across the engine swap that compaction
// performs (the StoreEngine Arc in `engines` is replaced; this guard is not).
//   * `gate`: write paths take `read()`; compaction takes `write()` to stop the
//     world for that store while it reads→builds→fsyncs→renames→swaps, so no
//     acknowledged write can land on the about-to-be-discarded old engine (B3).
//   * `compacting`: a CAS flag so a second concurrent compaction of the same
//     store is refused (`compaction_in_progress`) rather than silently doubled.
pub struct StoreGuard {
    pub gate: RwLock<()>,
    pub compacting: AtomicBool,
}

impl StoreGuard {
    fn new() -> Self {
        Self {
            gate: RwLock::new(()),
            compacting: AtomicBool::new(false),
        }
    }
}

pub fn is_valid_store_name(s: &str) -> bool {
    !s.is_empty()
        && s.chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
}

// ── Service Extensibility Trait Primitives ──────────────────────────────────

pub trait BackgroundService: Send + Sync {
    fn start(&self, kernel: Arc<ServerKernel>) -> Result<(), String>;
    #[allow(dead_code)]
    fn stop(&self);
}

pub trait RequestMiddleware: Send + Sync {
    fn before_request(
        &self,
        req: &mut serde_json::Value,
        kernel: &ServerKernel,
    ) -> Result<(), String>;
    fn after_response(
        &self,
        req: &serde_json::Value,
        resp: &mut serde_json::Value,
        kernel: &ServerKernel,
    );
}

// ── Registry Implementations ────────────────────────────────────────────────

pub type CommandHandler =
    Arc<dyn Fn(&serde_json::Value, &ServerKernel) -> serde_json::Value + Send + Sync>;

#[derive(Clone)]
pub struct CommandRegistry {
    pub routes: HashMap<String, CommandHandler>,
}

impl CommandRegistry {
    pub fn new() -> Self {
        Self {
            routes: HashMap::new(),
        }
    }

    pub fn register(&mut self, op: &str, handler: CommandHandler) {
        self.routes.insert(op.to_string(), handler);
    }

    pub fn call(
        &self,
        op: &str,
        req: &serde_json::Value,
        kernel: &ServerKernel,
    ) -> Option<serde_json::Value> {
        self.routes.get(op).map(|handler| handler(req, kernel))
    }
}

#[derive(Default, Clone)]
pub struct MiddlewareChain {
    pub middlewares: Vec<Arc<dyn RequestMiddleware>>,
}

impl MiddlewareChain {
    pub fn new() -> Self {
        Self {
            middlewares: Vec::new(),
        }
    }

    pub fn register(&mut self, middleware: Arc<dyn RequestMiddleware>) {
        self.middlewares.push(middleware);
    }
}

// ── The Server Kernel (Assembly Stage Container) ─────────────────────────────

pub struct ServerKernel {
    pub host: String,
    pub port: u16,
    pub engines: Arc<RwLock<HashMap<String, Arc<StoreEngine>>>>,
    pub data_dir: Option<String>,
    pub pool_size: usize,
    pub auth_enabled: bool,
    // LAB-TBACKEND-SERVER-CANONICAL-HASH-P4: when true, a fact whose client
    // `value_hash` disagrees with the server canonical hash is rejected
    // (`value_hash_mismatch`) instead of silently replaced. Default false for
    // compatibility with legacy SHA256/CRC32 clients; opt-in for audit mode.
    pub hash_strict: bool,
    // LAB-TBACKEND-SAFE-COMPACTION-STOP-THE-WORLD-P12: when false (default),
    // compaction is OFF — `snapshot_trigger` refuses (`compaction_disabled`) and
    // no background sweep runs. When true (`--enable-compaction true`), MANUAL
    // `snapshot_trigger` runs the SAFE path: a per-store stop-the-world lock
    // (no acked-write loss, B3) + durable tmp-fsync/rename/dir-fsync (B4) +
    // seq-preserving rebuild (B5). The background 5s sweep stays disabled in v0.
    // (Supersedes the P6 `--unsafe-compaction` gate, which is now removed.)
    pub compaction_enabled: bool,
    // Proof seams for the durable-rename path (P12): counts of file/dir fsyncs
    // actually issued by safe compaction.
    pub compaction_file_fsyncs: AtomicU64,
    pub compaction_dir_fsyncs: AtomicU64,
    // Per-store compaction guards (stop-the-world gate + in-progress flag),
    // stable across engine swaps. See `StoreGuard`.
    pub store_guards: RwLock<HashMap<String, Arc<StoreGuard>>>,
    // LAB-TBACKEND-DURABLE-ACK-GROUP-COMMIT-P6: ack durability vocabulary.
    // `durability_default` is the server-wide mode ("accepted" = current
    // flush/page-cache ack, survives process crash not power loss; "durable" =
    // waits for a group-commit fdatasync before ack). A per-request
    // `durability` field overrides it. `commit_interval_ms`/`commit_max_batch`
    // tune the group-commit window (one fdatasync amortized across the batch).
    pub durability_default: String,
    pub commit_interval_ms: u64,
    pub commit_max_batch: u64,

    // Active extensible registries
    pub command_registry: Arc<RwLock<CommandRegistry>>,
    pub middleware_chain: Arc<RwLock<MiddlewareChain>>,
    pub background_services: Arc<RwLock<Vec<Box<dyn BackgroundService>>>>,
}

impl ServerKernel {
    pub fn new(
        host: String,
        port: u16,
        data_dir: Option<String>,
        pool_size: usize,
        auth_enabled: bool,
        hash_strict: bool,
        compaction_enabled: bool,
        durability_default: String,
        commit_interval_ms: u64,
        commit_max_batch: u64,
    ) -> Self {
        Self {
            host,
            port,
            engines: Arc::new(RwLock::new(HashMap::new())),
            data_dir,
            pool_size,
            auth_enabled,
            hash_strict,
            compaction_enabled,
            compaction_file_fsyncs: AtomicU64::new(0),
            compaction_dir_fsyncs: AtomicU64::new(0),
            store_guards: RwLock::new(HashMap::new()),
            durability_default,
            commit_interval_ms,
            commit_max_batch,
            command_registry: Arc::new(RwLock::new(CommandRegistry::new())),
            middleware_chain: Arc::new(RwLock::new(MiddlewareChain::new())),
            background_services: Arc::new(RwLock::new(Vec::new())),
        }
    }

    /// Thread-safe dynamic resolver to get or load/warm-up a database store engine.
    pub fn get_or_create_engine(&self, store_name: &str) -> Option<Arc<StoreEngine>> {
        if !is_valid_store_name(store_name) {
            return None;
        }
        {
            let map = self.engines.read();
            if let Some(engine) = map.get(store_name) {
                return Some(engine.clone());
            }
        }
        let mut map = self.engines.write();
        if let Some(engine) = map.get(store_name) {
            return Some(engine.clone());
        }

        let log = Arc::new(ShardedFactLog::new());
        let wal = if let Some(ref dir) = self.data_dir {
            let path = format!("{}/{}.wal", dir, store_name);
            match FileBackend::new_pure(&path) {
                Ok(fb) => {
                    let wal_arc = Arc::new(fb);
                    if let Ok(facts) = wal_arc.replay_pure() {
                        // Restore facts AND the per-store seq_id counter
                        // (next_seq = max replayed seq + 1; legacy seq=0 backfilled
                        // by append order). LAB-TBACKEND-SEQID-PER-STORE-P9.
                        log.load_replayed(facts);
                    }
                    Some(wal_arc)
                }
                Err(e) => {
                    println!(
                        "[TBackend Server] Error initializing WAL file for {}: {}",
                        store_name, e
                    );
                    None
                }
            }
        } else {
            None
        };

        let engine = Arc::new(StoreEngine { log, wal });
        map.insert(store_name.to_string(), engine.clone());
        Some(engine)
    }

    /// Get-or-create the per-store compaction guard. Stable across engine swaps
    /// (LAB-TBACKEND-SAFE-COMPACTION-STOP-THE-WORLD-P12). Write paths take
    /// `gate.read()`; compaction takes `gate.write()`.
    pub fn store_guard(&self, store_name: &str) -> Arc<StoreGuard> {
        {
            let map = self.store_guards.read();
            if let Some(g) = map.get(store_name) {
                return g.clone();
            }
        }
        let mut map = self.store_guards.write();
        map.entry(store_name.to_string())
            .or_insert_with(|| Arc::new(StoreGuard::new()))
            .clone()
    }
}

// ── Packs & Manifest Contracts ──────────────────────────────────────────────

pub struct PackManifest {
    pub name: &'static str,
    pub requires_packs: Vec<&'static str>,
    pub provides_capabilities: Vec<&'static str>,
    pub requires_capabilities: Vec<&'static str>,
}

pub trait ServerPack: Send + Sync {
    fn manifest(&self) -> PackManifest;
    fn install_into(&self, kernel: &mut ServerKernel) -> Result<(), String>;
}

// ── Compiled Server Profile ──────────────────────────────────────────────────

#[derive(Clone)]
pub struct ServerProfile {
    pub fingerprint: String,
    pub active_packs: Vec<&'static str>,
    pub command_registry: CommandRegistry,
    pub middleware_chain: MiddlewareChain,
}

pub struct ProfileAssembler {
    installed_packs: Vec<Box<dyn ServerPack>>,
}

impl ProfileAssembler {
    pub fn new() -> Self {
        Self {
            installed_packs: Vec::new(),
        }
    }

    pub fn register_pack(&mut self, pack: Box<dyn ServerPack>) {
        self.installed_packs.push(pack);
    }

    pub fn finalize(
        self,
        mut kernel: ServerKernel,
    ) -> Result<(ServerProfile, ServerKernel), String> {
        // 1. Recursive Dependency & Capabilities Completeness Verification
        for pack in &self.installed_packs {
            let manifest = pack.manifest();

            // Validate required packs are loaded
            for req in &manifest.requires_packs {
                let found = self
                    .installed_packs
                    .iter()
                    .any(|p| p.manifest().name == *req);
                if !found {
                    return Err(format!(
                        "Completeness Error: Pack '{}' requires pack '{}', but it is missing from configuration.",
                        manifest.name, req
                    ));
                }
            }

            // Validate required capabilities are supplied by at least one package
            for req_cap in &manifest.requires_capabilities {
                let found = self
                    .installed_packs
                    .iter()
                    .any(|p| p.manifest().provides_capabilities.contains(req_cap));
                if !found {
                    return Err(format!(
                        "Completeness Error: Pack '{}' requires capability '{}', but no registered pack provides it.",
                        manifest.name, req_cap
                    ));
                }
            }
        }

        // 2. Perform mounts (run install_into on each pack)
        for pack in &self.installed_packs {
            pack.install_into(&mut kernel)?;
        }

        // 3. Compute Cryptographic Configuration Fingerprint (using blake3)
        let mut hasher = blake3::Hasher::new();
        // Add names of active packs deterministically
        let mut sorted_packs: Vec<&'static str> = self
            .installed_packs
            .iter()
            .map(|p| p.manifest().name)
            .collect();
        sorted_packs.sort();
        for name in &sorted_packs {
            hasher.update(name.as_bytes());
        }
        let fingerprint = hasher.finalize().to_hex().to_string();

        let active_packs = self
            .installed_packs
            .iter()
            .map(|p| p.manifest().name)
            .collect();
        let cmd_reg = kernel.command_registry.read().clone();
        let mid_chain = kernel.middleware_chain.read().clone();

        let profile = ServerProfile {
            fingerprint,
            active_packs,
            command_registry: cmd_reg,
            middleware_chain: mid_chain,
        };

        Ok((profile, kernel))
    }
}
