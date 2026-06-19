//! Local-loopback `igniter-server` binary (LAB-MACHINE-IGNITER-SERVER-BINARY-P2).
//!
//! Binds `127.0.0.1` ONLY, serves a bounded number of requests through the fixture `ServerApp`, then
//! exits. No daemon, no public listener, no web framework, no SparkCRM, no DB/live.
//!
//! Usage: `igniter-server [port] [max_requests]`
//!   port          default 0 (OS-assigned; the bound addr is printed so a client can connect)
//!   max_requests  default 1
//!
//! Routing lives entirely in `fixture::DemoApp` — the binary holds no route table.

use igniter_server::fixture::DemoApp;
use igniter_server::host::serve_bounded;
use std::net::TcpListener;

fn main() -> std::io::Result<()> {
    let mut args = std::env::args().skip(1);
    let port: u16 = args.next().and_then(|s| s.parse().ok()).unwrap_or(0);
    let max_requests: usize = args.next().and_then(|s| s.parse().ok()).unwrap_or(1);

    // loopback ONLY — never a public address.
    let listener = TcpListener::bind(("127.0.0.1", port))?;
    let addr = listener.local_addr()?;
    println!(
        "igniter-server listening on http://{addr} (loopback, {max_requests} request(s) then exit)"
    );

    let app = DemoApp;
    let served = serve_bounded(&listener, &app, max_requests)?;
    println!("igniter-server served {served} request(s); exiting");
    Ok(())
}
