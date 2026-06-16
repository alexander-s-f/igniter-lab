use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum EngineError {
    StorageError(String),
    IOError(String),
    SerializationError(String),
    CompilationError(String),
    VMExecutionError(String),
    /// An on-disk fact file could not be decoded. Surfaced (never silently treated as empty) so
    /// corruption is observable instead of presenting as lost history. (LAB-MACHINE-FACTSTORE-
    /// DURABILITY-HARDENING-P3.)
    Corruption(String),
    NotFound,
}

impl std::fmt::Display for EngineError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            EngineError::StorageError(e) => write!(f, "Storage error: {}", e),
            EngineError::IOError(e) => write!(f, "IO error: {}", e),
            EngineError::SerializationError(e) => write!(f, "Serialization error: {}", e),
            EngineError::CompilationError(e) => write!(f, "Compilation error: {}", e),
            EngineError::VMExecutionError(e) => write!(f, "VM execution error: {}", e),
            EngineError::Corruption(e) => write!(f, "Corrupt fact file: {}", e),
            EngineError::NotFound => write!(f, "Not found"),
        }
    }
}

impl std::error::Error for EngineError {}
