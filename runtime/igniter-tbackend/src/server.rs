use crate::fact::FactData;
use crate::timeline::ShardedFactLog;
use crate::wal::FileBackend;
use magnus::{value::ReprValue, Error, TryConvert, Value};
use parking_lot::Mutex;
use serde::Deserialize;
use serde_json::json;
use std::collections::HashMap;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::channel;
use std::sync::Arc;
use std::thread;
use std::time::Instant;

#[derive(Deserialize)]
struct Request {
    op: String,
    store: Option<String>,
    key: Option<String>,
    as_of: Option<f64>,
    since: Option<f64>,
    filters: Option<serde_json::Value>,
    fact: Option<FactData>,
}

pub struct MetricsTracker {
    pub total_requests: AtomicU64,
    pub active_connections: AtomicU64,
    pub errors_encountered: AtomicU64,
    pub bytes_read: AtomicU64,
    pub bytes_written: AtomicU64,
    pub ping_ops: AtomicU64,
    pub write_fact_ops: AtomicU64,
    pub latest_for_ops: AtomicU64,
    pub facts_for_ops: AtomicU64,
    pub query_scope_ops: AtomicU64,
    pub size_ops: AtomicU64,
    pub metrics_ops: AtomicU64,
    pub total_latency_us: AtomicU64,
}

impl MetricsTracker {
    pub fn new() -> Self {
        Self {
            total_requests: AtomicU64::new(0),
            active_connections: AtomicU64::new(0),
            errors_encountered: AtomicU64::new(0),
            bytes_read: AtomicU64::new(0),
            bytes_written: AtomicU64::new(0),
            ping_ops: AtomicU64::new(0),
            write_fact_ops: AtomicU64::new(0),
            latest_for_ops: AtomicU64::new(0),
            facts_for_ops: AtomicU64::new(0),
            query_scope_ops: AtomicU64::new(0),
            size_ops: AtomicU64::new(0),
            metrics_ops: AtomicU64::new(0),
            total_latency_us: AtomicU64::new(0),
        }
    }

    pub fn to_json(&self) -> serde_json::Value {
        let reqs = self.total_requests.load(Ordering::Relaxed);
        let lat = self.total_latency_us.load(Ordering::Relaxed);
        let avg_lat = if reqs > 0 {
            lat as f64 / reqs as f64
        } else {
            0.0
        };

        serde_json::json!({
            "total_requests": reqs,
            "active_connections": self.active_connections.load(Ordering::Relaxed),
            "errors_encountered": self.errors_encountered.load(Ordering::Relaxed),
            "bytes_read": self.bytes_read.load(Ordering::Relaxed),
            "bytes_written": self.bytes_written.load(Ordering::Relaxed),
            "ops": {
                "ping": self.ping_ops.load(Ordering::Relaxed),
                "write_fact": self.write_fact_ops.load(Ordering::Relaxed),
                "latest_for": self.latest_for_ops.load(Ordering::Relaxed),
                "facts_for": self.facts_for_ops.load(Ordering::Relaxed),
                "query_scope": self.query_scope_ops.load(Ordering::Relaxed),
                "size": self.size_ops.load(Ordering::Relaxed),
                "metrics": self.metrics_ops.load(Ordering::Relaxed),
            },
            "total_latency_us": lat,
            "average_latency_us": avg_lat,
        })
    }
}

struct ConnectionGuard {
    metrics: Arc<MetricsTracker>,
}

impl Drop for ConnectionGuard {
    fn drop(&mut self) {
        self.metrics
            .active_connections
            .fetch_sub(1, Ordering::Relaxed);
    }
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

pub struct StoreEngine {
    pub log: Arc<ShardedFactLog>,
    pub wal: Option<Arc<FileBackend>>,
}

fn is_valid_store_name(s: &str) -> bool {
    !s.is_empty()
        && s.chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
}

fn get_or_create_engine(
    store_name: &str,
    engines: &Arc<parking_lot::RwLock<HashMap<String, Arc<StoreEngine>>>>,
    data_dir: &Option<String>,
) -> Arc<StoreEngine> {
    {
        let map = engines.read();
        if let Some(engine) = map.get(store_name) {
            return engine.clone();
        }
    }
    let mut map = engines.write();
    if let Some(engine) = map.get(store_name) {
        return engine.clone();
    }

    let log = Arc::new(ShardedFactLog::new());
    let wal = if let Some(ref dir) = data_dir {
        let path = format!("{}/{}.wal", dir, store_name);
        match FileBackend::new_pure(&path) {
            Ok(fb) => {
                let wal_arc = Arc::new(fb);
                if let Ok(facts) = wal_arc.replay_pure() {
                    for fact in facts {
                        log.push(fact);
                    }
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
    engine
}

fn handle_request(
    req_bytes: &[u8],
    engines: &Arc<parking_lot::RwLock<HashMap<String, Arc<StoreEngine>>>>,
    data_dir: &Option<String>,
    metrics: &Arc<MetricsTracker>,
) -> serde_json::Value {
    let req: Request = match serde_json::from_slice(req_bytes) {
        Ok(r) => r,
        Err(e) => {
            metrics.errors_encountered.fetch_add(1, Ordering::Relaxed);
            return json!({ "ok": false, "error": format!("Invalid JSON request: {}", e) });
        }
    };

    match req.op.as_str() {
        "ping" => {
            metrics.ping_ops.fetch_add(1, Ordering::Relaxed);
            json!({ "ok": true, "pong": true })
        }
        "write_fact" => {
            metrics.write_fact_ops.fetch_add(1, Ordering::Relaxed);
            if let Some(data) = req.fact {
                let store_name = &data.store;
                if !is_valid_store_name(store_name) {
                    metrics.errors_encountered.fetch_add(1, Ordering::Relaxed);
                    return json!({ "ok": false, "error": "Invalid store name" });
                }
                let engine = get_or_create_engine(store_name, engines, data_dir);
                if let Some(ref fb) = engine.wal {
                    if let Err(e) = fb.write_fact_data(&data) {
                        metrics.errors_encountered.fetch_add(1, Ordering::Relaxed);
                        return json!({ "ok": false, "error": format!("WAL write failed: {}", e) });
                    }
                }
                engine.log.push(data);
                json!({ "ok": true })
            } else {
                metrics.errors_encountered.fetch_add(1, Ordering::Relaxed);
                json!({ "ok": false, "error": "Missing 'fact' parameter for write_fact" })
            }
        }
        "latest_for" => {
            metrics.latest_for_ops.fetch_add(1, Ordering::Relaxed);
            if let (Some(ref store), Some(ref key)) = (req.store, req.key) {
                if !is_valid_store_name(store) {
                    metrics.errors_encountered.fetch_add(1, Ordering::Relaxed);
                    return json!({ "ok": false, "error": "Invalid store name" });
                }
                let engine = get_or_create_engine(store, engines, data_dir);
                let found = engine.log.latest_for(store, key, req.as_of);
                json!({ "ok": true, "fact": found })
            } else {
                metrics.errors_encountered.fetch_add(1, Ordering::Relaxed);
                json!({ "ok": false, "error": "Missing 'store' or 'key' parameter" })
            }
        }
        "facts_for" => {
            metrics.facts_for_ops.fetch_add(1, Ordering::Relaxed);
            if let Some(ref store) = req.store {
                if !is_valid_store_name(store) {
                    metrics.errors_encountered.fetch_add(1, Ordering::Relaxed);
                    return json!({ "ok": false, "error": "Invalid store name" });
                }
                let engine = get_or_create_engine(store, engines, data_dir);
                let facts = if let Some(ref key) = req.key {
                    engine.log.facts_for_key(store, key, req.since, req.as_of)
                } else {
                    engine.log.facts_for_store(store, req.since, req.as_of)
                };
                json!({ "ok": true, "facts": facts })
            } else {
                metrics.errors_encountered.fetch_add(1, Ordering::Relaxed);
                json!({ "ok": false, "error": "Missing 'store' parameter" })
            }
        }
        "query_scope" => {
            metrics.query_scope_ops.fetch_add(1, Ordering::Relaxed);
            if let (Some(ref store), Some(ref filters)) = (req.store, req.filters) {
                if !is_valid_store_name(store) {
                    metrics.errors_encountered.fetch_add(1, Ordering::Relaxed);
                    return json!({ "ok": false, "error": "Invalid store name" });
                }
                let engine = get_or_create_engine(store, engines, data_dir);
                let facts = engine.log.query_scope(store, filters, req.as_of);
                json!({ "ok": true, "facts": facts })
            } else {
                metrics.errors_encountered.fetch_add(1, Ordering::Relaxed);
                json!({ "ok": false, "error": "Missing 'store' or 'filters' parameter" })
            }
        }
        "size" => {
            metrics.size_ops.fetch_add(1, Ordering::Relaxed);
            if let Some(ref store) = req.store {
                if !is_valid_store_name(store) {
                    metrics.errors_encountered.fetch_add(1, Ordering::Relaxed);
                    return json!({ "ok": false, "error": "Invalid store name" });
                }
                let engine = get_or_create_engine(store, engines, data_dir);
                json!({ "ok": true, "size": engine.log.size() })
            } else {
                let total: usize = engines.read().values().map(|e| e.log.size()).sum();
                json!({ "ok": true, "size": total })
            }
        }
        "stores" => {
            let names: Vec<String> = engines.read().keys().cloned().collect();
            json!({ "ok": true, "stores": names })
        }
        "metrics" => {
            metrics.metrics_ops.fetch_add(1, Ordering::Relaxed);
            metrics.to_json()
        }
        other => {
            metrics.errors_encountered.fetch_add(1, Ordering::Relaxed);
            json!({ "ok": false, "error": format!("Unknown operation: {}", other) })
        }
    }
}

#[magnus::wrap(class = "Igniter::TBackendPlayground::Server", free_immediately, size)]
#[allow(dead_code)]
pub struct Server {
    engines: Arc<parking_lot::RwLock<HashMap<String, Arc<StoreEngine>>>>,
    data_dir: Option<String>,
    shutdown_tx: parking_lot::Mutex<Option<std::sync::mpsc::Sender<()>>>,
    metrics: Arc<MetricsTracker>,
}

impl Server {
    pub fn rb_start(
        host: String,
        port: u16,
        data_dir_val: Value,
        pool_size_val: Value,
    ) -> Result<Self, Error> {
        let data_dir = if data_dir_val.is_nil() {
            None
        } else {
            let dir: String = TryConvert::try_convert(data_dir_val)?;
            Some(dir)
        };

        let pool_size = if pool_size_val.is_nil() {
            16
        } else {
            match TryConvert::try_convert(pool_size_val) {
                Ok(x) => x,
                Err(_) => {
                    return Err(Error::new(
                        magnus::exception::runtime_error(),
                        "thread_pool_size must be an integer",
                    ))
                }
            }
        };

        let engines = Arc::new(parking_lot::RwLock::new(HashMap::new()));

        // If data_dir is set, scan it for existing *.wal files and preload them!
        if let Some(ref dir) = data_dir {
            let _ = std::fs::create_dir_all(dir);
            if let Ok(entries) = std::fs::read_dir(dir) {
                for entry in entries {
                    if let Ok(entry) = entry {
                        let path = entry.path();
                        if path.is_file() && path.extension().map_or(false, |ext| ext == "wal") {
                            if let Some(stem) = path.file_stem() {
                                if let Some(store_name) = stem.to_str() {
                                    if is_valid_store_name(store_name) {
                                        println!("[TBackend Server] Preloading dynamic store engine '{}' from disk...", store_name);
                                        get_or_create_engine(store_name, &engines, &data_dir);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        let listener = TcpListener::bind(format!("{}:{}", host, port)).map_err(|e| {
            Error::new(
                magnus::exception::runtime_error(),
                format!("Bind failed: {}", e),
            )
        })?;

        let (shutdown_tx, shutdown_rx) = std::sync::mpsc::channel::<()>();

        let metrics = Arc::new(MetricsTracker::new());
        let metrics_t = metrics.clone();

        // Custom thread-safe connection distribution queue
        let (tx, rx) = channel::<TcpStream>();
        let rx = Arc::new(Mutex::new(rx));

        let engines_t = engines.clone();
        let data_dir_t = data_dir.clone();

        // Spawn fixed worker thread pool
        for i in 0..pool_size {
            let rx_c = rx.clone();
            let engines_c = engines_t.clone();
            let data_dir_c = data_dir_t.clone();
            let metrics_c = metrics_t.clone();

            thread::spawn(move || {
                loop {
                    // Block worker thread until a connection is available in the queue
                    let mut stream = match rx_c.lock().recv() {
                        Ok(s) => s,
                        Err(_) => break, // Channel closed, gracefully exit worker thread
                    };

                    let _ = stream.set_nodelay(true);
                    let _ = stream.set_nonblocking(false); // Explicitly ensure stream is blocking (crucial for non-blocking listener inherits on macOS)!
                    let _ = stream.set_read_timeout(Some(std::time::Duration::from_secs(30))); // Prevent slot starvation

                    metrics_c.active_connections.fetch_add(1, Ordering::Relaxed);
                    let _guard = ConnectionGuard {
                        metrics: metrics_c.clone(),
                    };

                    loop {
                        match read_frame(&mut stream) {
                            Ok(Some((body, bytes_read))) => {
                                metrics_c.total_requests.fetch_add(1, Ordering::Relaxed);
                                metrics_c
                                    .bytes_read
                                    .fetch_add(bytes_read as u64, Ordering::Relaxed);

                                let start_time = Instant::now();
                                let resp =
                                    handle_request(&body, &engines_c, &data_dir_c, &metrics_c);
                                let elapsed = start_time.elapsed().as_micros() as u64;
                                metrics_c
                                    .total_latency_us
                                    .fetch_add(elapsed, Ordering::Relaxed);

                                let resp_bytes = serde_json::to_vec(&resp).unwrap_or_default();
                                match write_frame(&mut stream, &resp_bytes) {
                                    Ok(bytes_written) => {
                                        metrics_c
                                            .bytes_written
                                            .fetch_add(bytes_written as u64, Ordering::Relaxed);
                                    }
                                    Err(e) => {
                                        metrics_c
                                            .errors_encountered
                                            .fetch_add(1, Ordering::Relaxed);
                                        println!("[Worker Thread {}] Write error: {}", i, e);
                                        break;
                                    }
                                }
                            }
                            Ok(None) => {
                                break;
                            }
                            Err(e) => {
                                metrics_c.errors_encountered.fetch_add(1, Ordering::Relaxed);
                                println!("[Worker Thread {}] Read error: {}", i, e);
                                break;
                            }
                        }
                    }
                }
            });
        }

        // Listener loop queue dispatcher
        thread::spawn(move || {
            let _ = listener.set_nonblocking(true);
            loop {
                if shutdown_rx.try_recv().is_ok() {
                    break;
                }

                let stream = match listener.accept() {
                    Ok((s, _)) => s,
                    Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                        thread::sleep(std::time::Duration::from_millis(10));
                        continue;
                    }
                    Err(_) => break,
                };

                // Dispatch connection into the worker pool queue
                if tx.send(stream).is_err() {
                    break; // Workers have closed
                }
            }
        });

        Ok(Server {
            engines,
            data_dir,
            shutdown_tx: parking_lot::Mutex::new(Some(shutdown_tx)),
            metrics,
        })
    }

    pub fn rb_stop(&self) {
        if let Some(tx) = self.shutdown_tx.lock().take() {
            let _ = tx.send(());
        }
    }

    pub fn rb_metrics(&self) -> String {
        serde_json::to_string(&self.metrics.to_json()).unwrap_or_default()
    }
}
