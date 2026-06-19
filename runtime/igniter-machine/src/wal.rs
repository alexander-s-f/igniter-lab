use crate::errors::EngineError;
use crate::fact::Fact;
use parking_lot::Mutex;
use std::fs::{File, OpenOptions};
use std::io::{BufWriter, Read, Write};
use std::path::{Path, PathBuf};

pub struct WALWriter {
    path: PathBuf,
    writer: Mutex<BufWriter<File>>,
}

impl WALWriter {
    pub fn new(path: &Path) -> Result<Self, EngineError> {
        let file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(path)
            .map_err(|e| EngineError::IOError(e.to_string()))?;
        Ok(Self {
            path: path.to_path_buf(),
            writer: Mutex::new(BufWriter::new(file)),
        })
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

        Ok(())
    }

    pub fn replay(&self) -> Result<Vec<Fact>, EngineError> {
        if !self.path.exists() {
            return Ok(Vec::new());
        }
        let mut file = File::open(&self.path).map_err(|e| EngineError::IOError(e.to_string()))?;
        let mut results = Vec::new();
        loop {
            let mut len_buf = [0u8; 4];
            match file.read_exact(&mut len_buf) {
                Ok(_) => {}
                Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => break,
                Err(e) => return Err(EngineError::IOError(e.to_string())),
            }
            let body_len = u32::from_be_bytes(len_buf) as usize;

            let mut body = vec![0u8; body_len];
            if file.read_exact(&mut body).is_err() {
                break;
            }

            let mut crc_buf = [0u8; 4];
            if file.read_exact(&mut crc_buf).is_err() {
                break;
            }
            if u32::from_be_bytes(crc_buf) != crc32fast::hash(&body) {
                break;
            }

            let fact: Fact = match rmp_serde::from_slice(&body) {
                Ok(f) => f,
                Err(_) => continue,
            };
            results.push(fact);
        }
        Ok(results)
    }
}
