// src/packs/multitenant_scanner.rs
// Multi-Tenant Directory Cache Preloading Pack for TBackend

use crate::kernel::{is_valid_store_name, PackManifest, ServerKernel, ServerPack};

pub struct MultiTenantScannerPack;

impl MultiTenantScannerPack {
    pub fn new() -> Self {
        Self
    }
}

impl ServerPack for MultiTenantScannerPack {
    fn manifest(&self) -> PackManifest {
        PackManifest {
            name: "multitenant_scanner",
            requires_packs: vec![],
            provides_capabilities: vec!["cache_warmup"],
            requires_capabilities: vec![],
        }
    }

    fn install_into(&self, kernel: &mut ServerKernel) -> Result<(), String> {
        if let Some(ref dir) = kernel.data_dir {
            println!("[TBackend Kernel] Initializing storage directory: {}", dir);
            let _ = std::fs::create_dir_all(dir);
            if let Ok(entries) = std::fs::read_dir(dir) {
                for entry in entries {
                    if let Ok(entry) = entry {
                        let path = entry.path();
                        if path.is_file() && path.extension().map_or(false, |ext| ext == "wal") {
                            if let Some(stem) = path.file_stem() {
                                if let Some(store_name) = stem.to_str() {
                                    if is_valid_store_name(store_name) {
                                        println!("  [Cache Warmer] Preloading store engine '{}' from disk...", store_name);
                                        // Dynamic warm-up loading
                                        kernel.get_or_create_engine(store_name);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        Ok(())
    }
}
