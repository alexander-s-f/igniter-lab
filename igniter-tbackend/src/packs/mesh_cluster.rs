// src/packs/mesh_cluster.rs
// Distributed P2P Bitemporal Mesh Cluster and Gossip Sync Pack for TBackend

use crate::kernel::{PackManifest, ServerKernel, ServerPack, BackgroundService};
use crate::pure_core::FactData;
use std::collections::HashMap;
use std::net::{TcpStream};
use std::io::{Read, Write};
use std::sync::Arc;
use std::thread;

// ── Local Big-Endian Framing Decoders/Encoders ─────────────────────────────

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
        return Err(std::io::Error::new(std::io::ErrorKind::InvalidData, "CRC mismatch"));
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

// ── Mesh Cluster Synchronization Service (Background thread) ─────────────────

pub struct MeshSyncService {
    peers: Vec<String>,
}

impl MeshSyncService {
    pub fn new(peers: Vec<String>) -> Self {
        Self { peers }
    }
}

impl BackgroundService for MeshSyncService {
    fn start(&self, kernel: Arc<ServerKernel>) -> Result<(), String> {
        let peers = self.peers.clone();
        if peers.is_empty() {
            println!("[TBackend Mesh] Operating in Standalone node mode (no peers configured).");
            return Ok(());
        }

        println!("[TBackend Mesh] Booting P2P Gossip Sync thread. Peers: {:?}", peers);
        
        thread::spawn(move || {
            let mut rng_idx = 0;
            loop {
                // Sleep for 3 seconds before next gossip cycle
                thread::sleep(std::time::Duration::from_secs(3));

                // Select peer round-robin
                let peer_addr = &peers[rng_idx % peers.len()];
                rng_idx += 1;

                // Attempt gossip state vector exchange and pull replication sync
                match perform_gossip_exchange(peer_addr, &kernel) {
                    Ok(sync_count) => {
                        if sync_count > 0 {
                            println!(
                                "\x1b[1m\x1b[32m[Mesh Sync] Replicated {} new bitemporal fact(s) from peer {}\x1b[0m",
                                sync_count, peer_addr
                            );
                        }
                    }
                    Err(_e) => {
                        // Suppress connection failure logs to keep console clean,
                        // but log in debugging if needed.
                    }
                }
            }
        });

        Ok(())
    }

    fn stop(&self) {
        // Exits automatically when daemon process stops
    }
}

// ── Peer Gossip Exchanges & Anti-Entropy Sync ────────────────────────────────

fn perform_gossip_exchange(peer_addr: &str, kernel: &ServerKernel) -> Result<usize, String> {
    // 1. Establish connection to peer
    let mut stream = TcpStream::connect(peer_addr).map_err(|e| e.to_string())?;
    stream.set_nodelay(true).map_err(|e| e.to_string())?;
    stream.set_read_timeout(Some(std::time::Duration::from_secs(4))).map_err(|e| e.to_string())?;
    stream.set_write_timeout(Some(std::time::Duration::from_secs(4))).map_err(|e| e.to_string())?;

    // 2. Query peer's active stores state vectors (mesh_gossip)
    let req = serde_json::json!({ "op": "mesh_gossip" });
    let req_bytes = serde_json::to_vec(&req).unwrap();
    write_frame(&mut stream, &req_bytes).map_err(|e| e.to_string())?;

    let (resp_bytes, _) = match read_frame(&mut stream).map_err(|e| e.to_string())? {
        Some(x) => x,
        None => return Err("EOF".to_string()),
    };
    let resp: serde_json::Value = serde_json::from_slice(&resp_bytes).map_err(|e| e.to_string())?;
    
    let peer_stores = match resp.get("stores").and_then(|v| v.as_object()) {
        Some(obj) => obj,
        None => return Ok(0),
    };

    let mut total_syncs = 0;
    
    // 3. For each store peer contains, compare max timestamps
    for (store_name, peer_time_val) in peer_stores {
        let peer_time = peer_time_val.as_f64().unwrap_or(0.0);

        // Get local max transaction time for this store
        let local_time = kernel.engines.read().get(store_name)
            .and_then(|engine| {
                engine.log.facts_for_store(store_name, None, None)
                    .last()
                    .map(|f| f.transaction_time)
            })
            .unwrap_or(0.0);

        // 4. If peer has newer updates, pull them and replay locally
        if peer_time > local_time {
            let pulled = pull_facts_from_peer(peer_addr, store_name, local_time, kernel)?;
            total_syncs += pulled;
        }
    }

    Ok(total_syncs)
}

fn pull_facts_from_peer(
    peer_addr: &str,
    store_name: &str,
    since_time: f64,
    kernel: &ServerKernel,
) -> Result<usize, String> {
    let mut stream = TcpStream::connect(peer_addr).map_err(|e| e.to_string())?;
    stream.set_nodelay(true).map_err(|e| e.to_string())?;

    // Pull segments committed *after* since_time
    let req = serde_json::json!({
        "op": "mesh_sync_pull",
        "store": store_name,
        "since_time": since_time
    });
    let req_bytes = serde_json::to_vec(&req).unwrap();
    write_frame(&mut stream, &req_bytes).map_err(|e| e.to_string())?;

    let (resp_bytes, _) = match read_frame(&mut stream).map_err(|e| e.to_string())? {
        Some(x) => x,
        None => return Err("EOF".to_string()),
    };
    let resp: serde_json::Value = serde_json::from_slice(&resp_bytes).map_err(|e| e.to_string())?;
    
    let facts_val = match resp.get("facts").and_then(|v| v.as_array()) {
        Some(arr) => arr,
        None => return Ok(0),
    };

    let engine = kernel.get_or_create_engine(store_name)
        .ok_or_else(|| "Invalid store name during sync".to_string())?;

    let mut new_count = 0;
    for f_val in facts_val {
        let fact: FactData = serde_json::from_value(f_val.clone()).map_err(|e| e.to_string())?;
        
        // Assert causal Git-style completeness (prevent timeline duplications)
        if !engine.log.contains_fact(&fact.store, &fact.key, &fact.id) {
            if let Some(ref fb) = engine.wal {
                let _ = fb.write_fact_data(&fact);
            }
            engine.log.push(fact);
            new_count += 1;
        }
    }

    Ok(new_count)
}

// ── Mesh Cluster Pack ────────────────────────────────────────────────────────

pub struct MeshClusterPack {
    peers: Vec<String>,
}

impl MeshClusterPack {
    pub fn new(peers: Vec<String>) -> Self {
        Self { peers }
    }
}

impl ServerPack for MeshClusterPack {
    fn manifest(&self) -> PackManifest {
        PackManifest {
            name: "mesh_cluster",
            requires_packs: vec!["base_audit"],
            provides_capabilities: vec!["gossip_sync", "replication"],
            requires_capabilities: vec!["bitemporal_ledger"],
        }
    }

    fn install_into(&self, kernel: &mut ServerKernel) -> Result<(), String> {
        let registry = &mut *kernel.command_registry.write();

        // 1. Register command "/mesh_ping"
        registry.register("mesh_ping", Arc::new(|_req, _kernel| {
            serde_json::json!({ "ok": true, "pong": true })
        }));

        // 2. Register command "/mesh_gossip"
        registry.register("mesh_gossip", Arc::new(|_req, kernel| {
            let mut stores = HashMap::new();
            let map = kernel.engines.read();
            for (name, engine) in map.iter() {
                let latest_time = engine.log.facts_for_store(name, None, None)
                    .last()
                    .map(|f| f.transaction_time)
                    .unwrap_or(0.0);
                stores.insert(name.clone(), latest_time);
            }
            serde_json::json!({ "ok": true, "stores": stores })
        }));

        // 3. Register command "/mesh_sync_pull"
        registry.register("mesh_sync_pull", Arc::new(|req, kernel| {
            let store = req.get("store").and_then(|v| v.as_str()).unwrap_or("");
            let since_time = req.get("since_time").and_then(|v| v.as_f64()).unwrap_or(0.0);

            // Epsilon arithmetic ensures we pull strictly greater updates
            let since = since_time + 0.000001;

            let engine = kernel.get_or_create_engine(store);
            let facts = if let Some(e) = engine {
                e.log.facts_for_store(store, Some(since), None)
            } else {
                Vec::new()
            };
            serde_json::json!({ "ok": true, "facts": facts })
        }));

        // 4. Register Gossip Sync Service
        let service = MeshSyncService::new(self.peers.clone());
        kernel.background_services.write().push(Box::new(service));

        Ok(())
    }
}
