use crate::fact::{Fact, FactData};
use magnus::{Error, IntoValue, RArray, Ruby};
use parking_lot::Mutex;
use std::fs::{File, OpenOptions};
use std::io::{BufWriter, Read, Seek, SeekFrom, Write};

struct FileBackendInner {
    path: String,
    writer: BufWriter<File>,
}

#[magnus::wrap(
    class = "Igniter::TBackendPlayground::FileBackend",
    free_immediately,
    size
)]
pub struct FileBackend(Mutex<FileBackendInner>);

impl FileBackend {
    pub fn rb_new(path: String) -> Result<Self, Error> {
        let file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&path)
            .map_err(|e| Error::new(magnus::exception::runtime_error(), e.to_string()))?;
        Ok(FileBackend(Mutex::new(FileBackendInner {
            path,
            writer: BufWriter::new(file),
        })))
    }

    pub fn new_pure(path: &str) -> Result<Self, std::io::Error> {
        let file = OpenOptions::new().create(true).append(true).open(path)?;
        Ok(FileBackend(Mutex::new(FileBackendInner {
            path: path.to_string(),
            writer: BufWriter::new(file),
        })))
    }

    pub fn replay_pure(&self) -> Result<Vec<FactData>, std::io::Error> {
        let path = self.0.lock().path.clone();

        let mut file = File::open(&path)?;
        file.seek(SeekFrom::Start(0))?;

        let mut results = Vec::new();
        loop {
            let mut len_buf = [0u8; 4];
            match file.read_exact(&mut len_buf) {
                Ok(_) => {}
                Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => break,
                Err(e) => return Err(e),
            }
            let body_len = u32::from_be_bytes(len_buf) as usize;

            let mut body = vec![0u8; body_len];
            if file.read_exact(&mut body).is_err() {
                break; // truncated record
            }

            let mut crc_buf = [0u8; 4];
            if file.read_exact(&mut crc_buf).is_err() {
                break;
            }
            if u32::from_be_bytes(crc_buf) != crc32fast::hash(&body) {
                break; // corrupted frame
            }

            let data: FactData = match rmp_serde::from_slice(&body) {
                Ok(d) => d,
                Err(_) => continue,
            };

            results.push(data);
        }
        Ok(results)
    }

    pub fn rb_write_fact(&self, rb_fact: &Fact) -> Result<(), Error> {
        self.write_fact_data(&rb_fact.0)
            .map_err(|e| Error::new(magnus::exception::runtime_error(), e))
    }

    pub fn write_fact_data(&self, data: &FactData) -> Result<(), String> {
        let body = rmp_serde::to_vec_named(data).map_err(|e| e.to_string())?;
        let crc = crc32fast::hash(&body);
        let mut inner = self.0.lock();
        inner
            .writer
            .write_all(&(body.len() as u32).to_be_bytes())
            .and_then(|_| inner.writer.write_all(&body))
            .and_then(|_| inner.writer.write_all(&crc.to_be_bytes()))
            .and_then(|_| inner.writer.flush())
            .map_err(|e| e.to_string())
    }

    pub fn rb_replay(&self) -> Result<RArray, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let path = self.0.lock().path.clone();

        let mut file = File::open(&path)
            .map_err(|e| Error::new(magnus::exception::runtime_error(), e.to_string()))?;
        file.seek(SeekFrom::Start(0))
            .map_err(|e| Error::new(magnus::exception::runtime_error(), e.to_string()))?;

        let arr = RArray::new();
        loop {
            let mut len_buf = [0u8; 4];
            match file.read_exact(&mut len_buf) {
                Ok(_) => {}
                Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => break,
                Err(e) => {
                    return Err(Error::new(
                        magnus::exception::runtime_error(),
                        e.to_string(),
                    ))
                }
            }
            let body_len = u32::from_be_bytes(len_buf) as usize;

            let mut body = vec![0u8; body_len];
            if file.read_exact(&mut body).is_err() {
                break; // truncated record
            }

            let mut crc_buf = [0u8; 4];
            if file.read_exact(&mut crc_buf).is_err() {
                break;
            }
            if u32::from_be_bytes(crc_buf) != crc32fast::hash(&body) {
                break; // corrupted frame
            }

            let data: FactData = match rmp_serde::from_slice(&body) {
                Ok(d) => d,
                Err(_) => continue,
            };

            arr.push(Fact(data).into_value_with(&ruby))?;
        }
        Ok(arr)
    }

    pub fn rb_close(&self) -> Result<(), Error> {
        self.0
            .lock()
            .writer
            .flush()
            .map_err(|e| Error::new(magnus::exception::runtime_error(), e.to_string()))
    }
}
