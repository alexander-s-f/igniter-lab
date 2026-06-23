// src/main.rs
// Standalone Compiled TBackend System Daemon (Modularized Profile Assembly)

mod kernel;
mod packs;
mod pure_core;

use kernel::{PackManifest, ProfileAssembler, ServerKernel, ServerPack};
use packs::{
    AnalyticsPack, AuthPack, BaseAuditPack, CrossStorePack, DiagnosticsPack, McpPack,
    MultiTenantScannerPack, PipelinePack, QueryPack, SnapshotPack, TriggerPack,
};
use pure_core::{FactData, WriteOnceResult};

use parking_lot::Mutex;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::mpsc::channel;
use std::sync::Arc;
use std::thread;
use std::time::Instant;

extern "C" {
    fn dup(fd: std::os::raw::c_int) -> std::os::raw::c_int;
    fn dup2(oldfd: std::os::raw::c_int, newfd: std::os::raw::c_int) -> std::os::raw::c_int;
}

// ── Baseline Command Frame Networking ────────────────────────────────────────

struct ConnectionGuard;

impl Drop for ConnectionGuard {
    fn drop(&mut self) {
        if let Some(metrics) = packs::base_audit::AUDIT_METRICS.get() {
            metrics.active_connections.fetch_sub(1, Ordering::Relaxed);
        }
    }
}

#[derive(Clone)]
struct InflightLimiter {
    max: usize,
    current: Arc<AtomicUsize>,
}

struct InflightPermit {
    current: Arc<AtomicUsize>,
}

impl Drop for InflightPermit {
    fn drop(&mut self) {
        self.current.fetch_sub(1, Ordering::AcqRel);
    }
}

impl InflightLimiter {
    fn new(max: usize) -> Option<Self> {
        if max == 0 {
            None
        } else {
            Some(Self {
                max,
                current: Arc::new(AtomicUsize::new(0)),
            })
        }
    }

    fn try_acquire(&self) -> Option<InflightPermit> {
        loop {
            let observed = self.current.load(Ordering::Acquire);
            if observed >= self.max {
                return None;
            }
            if self
                .current
                .compare_exchange(observed, observed + 1, Ordering::AcqRel, Ordering::Acquire)
                .is_ok()
            {
                return Some(InflightPermit {
                    current: self.current.clone(),
                });
            }
        }
    }
}

fn overload_response(max_inflight_requests: usize) -> serde_json::Value {
    serde_json::json!({
        "ok": false,
        "error": "TBackend overloaded: max in-flight request limit reached",
        "error_code": "overloaded",
        "committed": false,
        "retryable": true,
        "max_inflight_requests": max_inflight_requests
    })
}

fn read_frame(stream: &mut TcpStream) -> std::io::Result<Option<(Vec<u8>, usize)>> {
    let mut len_buf = [0u8; 4];
    if let Err(e) = stream.read_exact(&mut len_buf) {
        if e.kind() == std::io::ErrorKind::UnexpectedEof {
            return Ok(None);
        }
        return Err(e);
    }
    let len = u32::from_be_bytes(len_buf) as usize;

    let mut body = vec![0u8; len];
    stream.read_exact(&mut body)?;

    let mut crc_buf = [0u8; 4];
    stream.read_exact(&mut crc_buf)?;
    let crc = u32::from_be_bytes(crc_buf);

    if crc != crc32fast::hash(&body) {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            "CRC mismatch",
        ));
    }

    let total_read = 4 + len + 4;
    Ok(Some((body, total_read)))
}

fn write_frame(stream: &mut TcpStream, body: &[u8]) -> std::io::Result<usize> {
    let len = body.len() as u32;
    let crc = crc32fast::hash(body);

    stream.write_all(&len.to_be_bytes())?;
    stream.write_all(body)?;
    stream.write_all(&crc.to_be_bytes())?;
    stream.flush()?;

    let total_written = 4 + body.len() + 4;
    Ok(total_written)
}

// ── Baseline Core Pack ────────────────────────────────────────────────────────

struct CorePack;

impl ServerPack for CorePack {
    fn manifest(&self) -> PackManifest {
        PackManifest {
            name: "core",
            requires_packs: vec![],
            provides_capabilities: vec!["bitemporal_ledger"],
            requires_capabilities: vec![],
        }
    }

    fn install_into(&self, kernel: &mut ServerKernel) -> Result<(), String> {
        let registry = &mut *kernel.command_registry.write();

        // 1. ping
        registry.register(
            "ping",
            Arc::new(|_req, _kernel| serde_json::json!({ "ok": true, "pong": true })),
        );

        // 2. write_fact
        registry.register("write_fact", Arc::new(|req, kernel| {
            let data_val = match req.get("fact") {
                Some(f) => f,
                None => return serde_json::json!({ "ok": false, "error": "Missing 'fact' parameter" }),
            };
            let data: FactData = match serde_json::from_value(data_val.clone()) {
                Ok(d) => d,
                Err(e) => return serde_json::json!({ "ok": false, "error": format!("Invalid fact data: {}", e) }),
            };

            let engine = match kernel.get_or_create_engine(&data.store) {
                Some(e) => e,
                None => return serde_json::json!({ "ok": false, "error": "Invalid store name" }),
            };

            if let Some(ref fb) = engine.wal {
                if let Err(e) = fb.write_fact_data(&data) {
                    return serde_json::json!({ "ok": false, "error": format!("WAL write failed: {}", e) });
                }
            }
            engine.log.push(data);
            serde_json::json!({ "ok": true })
        }));

        // 3. write_fact_once
        registry.register("write_fact_once", Arc::new(|req, kernel| {
            let data_val = match req.get("fact") {
                Some(f) => f,
                None => return serde_json::json!({ "ok": false, "error": "Missing 'fact' parameter" }),
            };
            let data: FactData = match serde_json::from_value(data_val.clone()) {
                Ok(d) => d,
                Err(e) => return serde_json::json!({ "ok": false, "error": format!("Invalid fact data: {}", e) }),
            };

            let engine = match kernel.get_or_create_engine(&data.store) {
                Some(e) => e,
                None => return serde_json::json!({ "ok": false, "error": "Invalid store name" }),
            };

            let result = engine.log.push_once(data, |fact| {
                if let Some(ref fb) = engine.wal {
                    fb.write_fact_data(fact)?;
                }
                Ok(())
            });

            match result {
                Ok(WriteOnceResult::Inserted) => serde_json::json!({
                    "ok": true,
                    "committed": true,
                    "idempotent_replay": false
                }),
                Ok(WriteOnceResult::Replay) => serde_json::json!({
                    "ok": true,
                    "committed": true,
                    "idempotent_replay": true
                }),
                Ok(WriteOnceResult::Conflict { existing }) => serde_json::json!({
                    "ok": false,
                    "error": "Duplicate fact id conflict",
                    "error_code": "duplicate_fact_id_conflict",
                    "committed": false,
                    "retryable": false,
                    "existing_key": existing.key,
                    "existing_value_hash": existing.value_hash
                }),
                Err(e) => serde_json::json!({ "ok": false, "error": format!("WAL write failed: {}", e) }),
            }
        }));

        // 3. latest_for
        registry.register("latest_for", Arc::new(|req, kernel| {
            let store = match req.get("store").and_then(|v| v.as_str()) {
                Some(s) => s,
                None => return serde_json::json!({ "ok": false, "error": "Missing 'store' parameter" }),
            };
            let key = match req.get("key").and_then(|v| v.as_str()) {
                Some(k) => k,
                None => return serde_json::json!({ "ok": false, "error": "Missing 'key' parameter" }),
            };
            let as_of = req.get("as_of").and_then(|v| v.as_f64());

            let engine = match kernel.get_or_create_engine(store) {
                Some(e) => e,
                None => return serde_json::json!({ "ok": false, "error": "Invalid store name" }),
            };
            let found = engine.log.latest_for(store, key, as_of);
            serde_json::json!({ "ok": true, "fact": found })
        }));

        // 4. facts_for
        registry.register("facts_for", Arc::new(|req, kernel| {
            let store = match req.get("store").and_then(|v| v.as_str()) {
                Some(s) => s,
                None => return serde_json::json!({ "ok": false, "error": "Missing 'store' parameter" }),
            };
            let key = req.get("key").and_then(|v| v.as_str());
            let since = req.get("since").and_then(|v| v.as_f64());
            let as_of = req.get("as_of").and_then(|v| v.as_f64());

            let engine = match kernel.get_or_create_engine(store) {
                Some(e) => e,
                None => return serde_json::json!({ "ok": false, "error": "Invalid store name" }),
            };
            let facts = if let Some(k) = key {
                engine.log.facts_for_key(store, k, since, as_of)
            } else {
                engine.log.facts_for_store(store, since, as_of)
            };
            serde_json::json!({ "ok": true, "facts": facts })
        }));

        // 5. size
        registry.register(
            "size",
            Arc::new(|req, kernel| {
                if let Some(store) = req.get("store").and_then(|v| v.as_str()) {
                    let engine = match kernel.get_or_create_engine(store) {
                        Some(e) => e,
                        None => {
                            return serde_json::json!({ "ok": false, "error": "Invalid store name" })
                        }
                    };
                    serde_json::json!({ "ok": true, "size": engine.log.size() })
                } else {
                    let total: usize = kernel.engines.read().values().map(|e| e.log.size()).sum();
                    serde_json::json!({ "ok": true, "size": total })
                }
            }),
        );

        // 7. stores
        registry.register(
            "stores",
            Arc::new(|_req, kernel| {
                let names: Vec<String> = kernel.engines.read().keys().cloned().collect();
                serde_json::json!({ "ok": true, "stores": names })
            }),
        );

        Ok(())
    }
}

// ── Application Core Bootstrap ───────────────────────────────────────────────

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let mcp_enabled = args.iter().any(|arg| arg == "--mcp");

    let original_stdout_fd = if mcp_enabled {
        // 1. Duplicate stdout to preserve the raw client pipe stream before redirecting stdout to stderr
        let fd = unsafe { dup(1) };
        if fd < 0 {
            eprintln!("[MCP Server] Fatal Error: failed to duplicate stdout fd");
            std::process::exit(1);
        }
        // 2. Redirect stdout (fd 1) to stderr (fd 2) so any logging or debug printouts go to stderr
        if unsafe { dup2(2, 1) } < 0 {
            eprintln!("[MCP Server] Fatal Error: failed to redirect stdout to stderr");
            std::process::exit(1);
        }
        Some(fd)
    } else {
        None
    };

    println!("\x1b[1m\x1b[36m┌──────────────────────────────────────────────────────────────┐");
    println!("│        TBACKEND PROFILE-NATIVE SYSTEM DAEMON v2.0            │");
    println!("└──────────────────────────────────────────────────────────────┘\x1b[0m");

    // Default configuration values
    let mut host = "127.0.0.1".to_string();
    let mut port = 7401;
    let mut data_dir = Some("data".to_string());
    let mut pool_size = 16;
    let mut config_path = None;
    let mut peers: Vec<String> = Vec::new();
    let mut auth_enabled = false;
    let mut mcp_enabled = mcp_enabled;
    let mut max_inflight_requests = 0usize;

    // CLI argument parsing
    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--host" => {
                if i + 1 < args.len() {
                    host = args[i + 1].clone();
                    i += 2;
                } else {
                    eprintln!("Error: Missing value for --host");
                    std::process::exit(1);
                }
            }
            "--port" => {
                if i + 1 < args.len() {
                    port = args[i + 1].parse().expect("Port must be an integer");
                    i += 2;
                } else {
                    eprintln!("Error: Missing value for --port");
                    std::process::exit(1);
                }
            }
            "--data-dir" => {
                if i + 1 < args.len() {
                    let val = args[i + 1].clone();
                    data_dir = if val == "nil" || val.is_empty() {
                        None
                    } else {
                        Some(val)
                    };
                    i += 2;
                } else {
                    eprintln!("Error: Missing value for --data-dir");
                    std::process::exit(1);
                }
            }
            "--pool-size" => {
                if i + 1 < args.len() {
                    pool_size = args[i + 1].parse().expect("Pool size must be an integer");
                    i += 2;
                } else {
                    eprintln!("Error: Missing value for --pool-size");
                    std::process::exit(1);
                }
            }
            "--peers" => {
                if i + 1 < args.len() {
                    let val = args[i + 1].clone();
                    peers = val
                        .split(',')
                        .map(|s| s.trim().to_string())
                        .filter(|s| !s.is_empty())
                        .collect();
                    i += 2;
                } else {
                    eprintln!("Error: Missing value for --peers");
                    std::process::exit(1);
                }
            }
            "--config" => {
                if i + 1 < args.len() {
                    config_path = Some(args[i + 1].clone());
                    i += 2;
                } else {
                    eprintln!("Error: Missing value for --config");
                    std::process::exit(1);
                }
            }
            "--auth-enabled" => {
                if i + 1 < args.len() {
                    auth_enabled = args[i + 1].parse().unwrap_or(false);
                    i += 2;
                } else {
                    eprintln!("Error: Missing value for --auth-enabled");
                    std::process::exit(1);
                }
            }
            "--max-inflight-requests" => {
                if i + 1 < args.len() {
                    max_inflight_requests = args[i + 1]
                        .parse()
                        .expect("Max in-flight requests must be an integer");
                    i += 2;
                } else {
                    eprintln!("Error: Missing value for --max-inflight-requests");
                    std::process::exit(1);
                }
            }
            "--mcp" => {
                mcp_enabled = true;
                i += 1;
            }
            _ => {
                eprintln!("Unknown argument: {}", args[i]);
                println!("Usage: tbackend [--host <ip>] [--port <port>] [--data-dir <dir>] [--pool-size <num>] [--peers <comma_ips>] [--config <json_file>] [--auth-enabled <true/false>] [--max-inflight-requests <num>] [--mcp]");
                std::process::exit(1);
            }
        }
    }

    // Load JSON configuration if specified
    if let Some(path) = config_path {
        println!("Loading configuration from file: {}", path);
        match std::fs::read_to_string(&path) {
            Ok(file_content) => match serde_json::from_str::<serde_json::Value>(&file_content) {
                Ok(json) => {
                    if let Some(h) = json.get("host").and_then(|v| v.as_str()) {
                        host = h.to_string();
                    }
                    if let Some(p) = json.get("port").and_then(|v| v.as_u64()) {
                        port = p as u16;
                    }
                    if let Some(d) = json.get("data_dir").and_then(|v| v.as_str()) {
                        data_dir = if d == "nil" || d.is_empty() {
                            None
                        } else {
                            Some(d.to_string())
                        };
                    }
                    if let Some(ps) = json.get("thread_pool_size").and_then(|v| v.as_u64()) {
                        pool_size = ps as usize;
                    }
                    if let Some(p_array) = json.get("peers").and_then(|v| v.as_array()) {
                        peers = p_array
                            .iter()
                            .filter_map(|v| v.as_str())
                            .map(|s| s.to_string())
                            .collect();
                    } else if let Some(p_str) = json.get("peers").and_then(|v| v.as_str()) {
                        peers = p_str
                            .split(',')
                            .map(|s| s.trim().to_string())
                            .filter(|s| !s.is_empty())
                            .collect();
                    }
                    if let Some(ae) = json.get("auth_enabled").and_then(|v| v.as_bool()) {
                        auth_enabled = ae;
                    } else if let Some(ae) = json.get("auth_enabled").and_then(|v| v.as_str()) {
                        auth_enabled = ae.parse().unwrap_or(false);
                    }
                    if let Some(mi) = json.get("max_inflight_requests").and_then(|v| v.as_u64()) {
                        max_inflight_requests = mi as usize;
                    } else if let Some(mi) =
                        json.get("max_inflight_requests").and_then(|v| v.as_str())
                    {
                        max_inflight_requests = mi.parse().unwrap_or(0);
                    }
                    if let Some(me) = json.get("mcp_enabled").and_then(|v| v.as_bool()) {
                        mcp_enabled = me;
                    } else if let Some(me) = json.get("mcp_enabled").and_then(|v| v.as_str()) {
                        mcp_enabled = me.parse().unwrap_or(false);
                    }
                }
                Err(e) => {
                    eprintln!("Error: Failed to parse JSON config file: {}", e);
                    std::process::exit(1);
                }
            },
            Err(e) => {
                eprintln!("Error: Failed to read config file '{}': {}", path, e);
                std::process::exit(1);
            }
        }
    }

    // ── Build and Assemble Server Profiles ───────────────────────────────────

    let kernel = ServerKernel::new(host, port, data_dir, pool_size, auth_enabled);

    let mut assembler = ProfileAssembler::new();
    // Register structural packs
    assembler.register_pack(Box::new(CorePack));
    assembler.register_pack(Box::new(BaseAuditPack::new()));
    assembler.register_pack(Box::new(MultiTenantScannerPack::new()));
    assembler.register_pack(Box::new(TriggerPack::new()));
    assembler.register_pack(Box::new(AnalyticsPack::new()));
    assembler.register_pack(Box::new(CrossStorePack::new()));
    assembler.register_pack(Box::new(SnapshotPack::new()));
    assembler.register_pack(Box::new(DiagnosticsPack::new()));
    assembler.register_pack(Box::new(PipelinePack::new()));
    assembler.register_pack(Box::new(AuthPack::new()));
    assembler.register_pack(Box::new(QueryPack::new()));
    assembler.register_pack(Box::new(McpPack::new()));

    // Dynamically register MeshClusterPack if peers are provided
    if !peers.is_empty() {
        assembler.register_pack(Box::new(packs::MeshClusterPack::new(peers)));
    }

    // Finalize profile, resolving dependencies and checking capabilities
    let (profile, kernel) = assembler
        .finalize(kernel)
        .expect("Failed assembling server profile");
    let kernel = Arc::new(kernel);

    // Boot all active background services (Anti-Entropy Sync, Webhook dispatcher threads)
    {
        let services = kernel.background_services.read();
        for service in services.iter() {
            if let Err(e) = service.start(kernel.clone()) {
                eprintln!("[TBackend Kernel] Error starting background service: {}", e);
            }
        }
    }

    println!("\x1b[1m\x1b[32m✔ TBackend Profile Assembled Online!\x1b[0m");
    println!(
        "  Signature:   \x1b[1mBLAKE3:{}\x1b[0m",
        &profile.fingerprint[0..12]
    );
    println!("  Active Packs:\x1b[1m{:?}\x1b[0m", profile.active_packs);
    println!(
        "  Address:     \x1b[1m{}:{}\x1b[0m",
        kernel.host, kernel.port
    );
    println!("  Thread Pool: \x1b[1m{} workers\x1b[0m", kernel.pool_size);
    println!("  Auth Enabled:\x1b[1m{}\x1b[0m", kernel.auth_enabled);
    println!(
        "  Backpressure:\x1b[1m{} max in-flight requests\x1b[0m",
        if max_inflight_requests == 0 {
            "disabled".to_string()
        } else {
            max_inflight_requests.to_string()
        }
    );
    if let Some(ref dir) = kernel.data_dir {
        println!("  Data Folder: \x1b[1m{}\x1b[0m", dir);
    } else {
        println!("  Operating in EPHEMERAL / In-Memory only mode.");
    }

    if mcp_enabled {
        println!("\x1b[1m\x1b[32m[TBackend] Entering native stdio Model Context Protocol (MCP) server mode...\x1b[0m");
        packs::mcp::run_mcp_loop(kernel, profile, original_stdout_fd.unwrap());
        std::process::exit(0);
    }

    // Bind TCP Listener
    let listener = TcpListener::bind(format!("{}:{}", kernel.host, kernel.port))
        .expect("Failed to bind TCP listener. Port already in use?");

    let (tx, rx) = channel::<TcpStream>();
    let rx = Arc::new(Mutex::new(rx));
    let inflight_limiter = InflightLimiter::new(max_inflight_requests);

    // Spawn fixed worker thread pool executing profile-based command routes
    for i in 0..kernel.pool_size {
        let rx_c = rx.clone();
        let kernel_c = kernel.clone();
        let profile_c = profile.clone();
        let inflight_limiter_c = inflight_limiter.clone();

        thread::spawn(move || {
            loop {
                let mut stream = match rx_c.lock().recv() {
                    Ok(s) => s,
                    Err(_) => break, // Graceful exit on channel close
                };

                let _ = stream.set_nodelay(true);
                let _ = stream.set_nonblocking(false); // Explicitly ensure stream is blocking
                let _ = stream.set_read_timeout(Some(std::time::Duration::from_secs(30))); // Prevent slowloris

                if let Some(metrics) = packs::base_audit::AUDIT_METRICS.get() {
                    metrics.active_connections.fetch_add(1, Ordering::Relaxed);
                }
                let _guard = ConnectionGuard;

                loop {
                    match read_frame(&mut stream) {
                        Ok(Some((body, bytes_read))) => {
                            // 1. Let audit tracker intercept frame details
                            if let Some(metrics) = packs::base_audit::AUDIT_METRICS.get() {
                                metrics
                                    .bytes_read
                                    .fetch_add(bytes_read as u64, Ordering::Relaxed);
                            }

                            let start_time = Instant::now();

                            // 2. Parse request JSON
                            let mut req_val: serde_json::Value = match serde_json::from_slice(&body)
                            {
                                Ok(v) => v,
                                Err(e) => {
                                    if let Some(metrics) = packs::base_audit::AUDIT_METRICS.get() {
                                        metrics.errors_encountered.fetch_add(1, Ordering::Relaxed);
                                    }
                                    serde_json::json!({ "ok": false, "error": format!("Invalid JSON request: {}", e) })
                                }
                            };

                            // 3. Request routing through middlewares
                            let _inflight_permit = if req_val.get("error").is_none() {
                                match inflight_limiter_c.as_ref() {
                                    Some(limiter) => match limiter.try_acquire() {
                                        Some(permit) => Some(permit),
                                        None => {
                                            let resp = overload_response(limiter.max);
                                            if let Some(metrics) =
                                                packs::base_audit::AUDIT_METRICS.get()
                                            {
                                                metrics
                                                    .overload_rejections
                                                    .fetch_add(1, Ordering::Relaxed);
                                                metrics
                                                    .errors_encountered
                                                    .fetch_add(1, Ordering::Relaxed);
                                                let resp_bytes =
                                                    serde_json::to_vec(&resp).unwrap_or_default();
                                                match write_frame(&mut stream, &resp_bytes) {
                                                    Ok(bytes_written) => {
                                                        metrics.bytes_written.fetch_add(
                                                            bytes_written as u64,
                                                            Ordering::Relaxed,
                                                        );
                                                    }
                                                    Err(e) => {
                                                        eprintln!(
                                                            "[Worker Thread {}] Write error: {}",
                                                            i, e
                                                        );
                                                        break;
                                                    }
                                                }
                                            } else {
                                                let resp_bytes =
                                                    serde_json::to_vec(&resp).unwrap_or_default();
                                                if write_frame(&mut stream, &resp_bytes).is_err() {
                                                    break;
                                                }
                                            }
                                            continue;
                                        }
                                    },
                                    None => None,
                                }
                            } else {
                                None
                            };

                            let resp = if req_val.get("error").is_some() {
                                req_val
                            } else {
                                // 3a. Run before_request middlewares
                                let mut middleware_err = None;
                                for mw in &profile_c.middleware_chain.middlewares {
                                    if let Err(e) = mw.before_request(&mut req_val, &kernel_c) {
                                        middleware_err = Some(e);
                                        break;
                                    }
                                }

                                let mut resp_val = if let Some(err) = middleware_err {
                                    serde_json::json!({ "ok": false, "error": err })
                                } else {
                                    // 3b. Call command registry handler
                                    let op =
                                        req_val.get("op").and_then(|v| v.as_str()).unwrap_or("");
                                    match profile_c.command_registry.call(op, &req_val, &kernel_c) {
                                        Some(res) => res,
                                        None => {
                                            serde_json::json!({ "ok": false, "error": format!("Unknown operation: {}", op) })
                                        }
                                    }
                                };

                                // 3c. Run after_response middlewares
                                for mw in &profile_c.middleware_chain.middlewares {
                                    mw.after_response(&req_val, &mut resp_val, &kernel_c);
                                }

                                resp_val
                            };

                            // 4. Update Latency
                            let elapsed = start_time.elapsed().as_micros() as u64;
                            if let Some(metrics) = packs::base_audit::AUDIT_METRICS.get() {
                                metrics
                                    .total_latency_us
                                    .fetch_add(elapsed, Ordering::Relaxed);
                            }

                            // 5. Write response frame
                            let resp_bytes = serde_json::to_vec(&resp).unwrap_or_default();
                            if let Some(metrics) = packs::base_audit::AUDIT_METRICS.get() {
                                match write_frame(&mut stream, &resp_bytes) {
                                    Ok(bytes_written) => {
                                        metrics
                                            .bytes_written
                                            .fetch_add(bytes_written as u64, Ordering::Relaxed);
                                    }
                                    Err(e) => {
                                        metrics.errors_encountered.fetch_add(1, Ordering::Relaxed);
                                        eprintln!("[Worker Thread {}] Write error: {}", i, e);
                                        break;
                                    }
                                }
                            } else {
                                if write_frame(&mut stream, &resp_bytes).is_err() {
                                    break;
                                }
                            }
                        }
                        Ok(None) => break,
                        Err(_e) => {
                            if let Some(metrics) = packs::base_audit::AUDIT_METRICS.get() {
                                metrics.errors_encountered.fetch_add(1, Ordering::Relaxed);
                            }
                            break;
                        }
                    }
                }
            }
        });
    }

    // Set up ctrlc handler for graceful shutdown
    let shutdown_engines = kernel.engines.clone();
    ctrlc::set_handler(move || {
        println!("\n\x1b[1m\x1b[33m[TBackend] Graceful shutdown initiated...\x1b[0m");
        let map = shutdown_engines.read();
        for (name, engine) in map.iter() {
            if let Some(ref fb) = engine.wal {
                println!("[TBackend] Flushing store '{}' log index...", name);
                let _ = fb.flush_pure();
            }
        }
        println!("\x1b[1m\x1b[32m✔ WAL indexes synchronized. Offline.\x1b[0m\n");
        std::process::exit(0);
    })
    .expect("Error setting Ctrl-C handler");

    // Queue dispatcher loop
    let _ = listener.set_nonblocking(true);
    loop {
        let stream = match listener.accept() {
            Ok((s, _)) => s,
            Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                thread::sleep(std::time::Duration::from_millis(10));
                continue;
            }
            Err(_) => break,
        };

        if tx.send(stream).is_err() {
            break;
        }
    }
}
