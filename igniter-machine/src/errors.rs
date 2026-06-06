use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum EngineError {
    StorageError(String),
    IOError(String),
    SerializationError(String),
    CompilationError(String),
    VMExecutionError(String),
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
            EngineError::NotFound => write!(f, "Not found"),
        }
    }
}

impl std::error::Error for EngineError {}
