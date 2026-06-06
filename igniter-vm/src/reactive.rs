// src/reactive.rs
// Lightweight, zero-dependency asynchronous HTTP/1.1 webhook receiver

use std::sync::Arc;
use tokio::net::TcpListener;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

pub struct ReactiveListener {
    pub port: u16,
}

impl ReactiveListener {
    pub fn new(port: u16) -> Self {
        Self { port }
    }

    // Listens for incoming POST webhook dispatches, parsing bodies and invoking the callback
    pub async fn listen<F, Fut>(&self, callback: F) -> Result<(), String>
    where
        F: Fn(serde_json::Value) -> Fut + Send + Sync + 'static,
        Fut: std::future::Future<Output = ()> + Send + 'static,
    {
        let addr = format!("127.0.0.1:{}", self.port);
        let listener = TcpListener::bind(&addr).await
            .map_err(|e| format!("Failed to bind ReactiveListener to {}: {}", addr, e))?;

        let cb = Arc::new(callback);

        tokio::spawn(async move {
            while let Ok((mut stream, _)) = listener.accept().await {
                let cb_clone = cb.clone();
                tokio::spawn(async move {
                    let mut buffer = [0u8; 8192];
                    if let Ok(bytes_read) = stream.read(&mut buffer).await {
                        if bytes_read == 0 { return; }
                        let request_str = String::from_utf8_lossy(&buffer[..bytes_read]);

                        // Simple HTTP/1.1 POST parser extracting content body
                        if request_str.starts_with("POST") {
                            if let Some(body_start) = request_str.find("\r\n\r\n") {
                                let body = &request_str[body_start + 4..];
                                // Parse JSON payload fact
                                if let Ok(jv) = serde_json::from_str::<serde_json::Value>(body) {
                                    cb_clone(jv).await;
                                }
                            }
                        }
                    }

                    // Acknowledge remote webhook dispatcher with standard 200 OK
                    let response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK";
                    let _ = stream.write_all(response.as_bytes()).await;
                    let _ = stream.flush().await;
                });
            }
        });

        Ok(())
    }
}
