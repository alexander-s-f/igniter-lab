//! LAB-FRAME-VIEW-FORM-DESUGAR — emit the `.ig` for a terse `.form` file.
//!
//! Usage: `cargo run --no-default-features --example desugar -- <path/to/file.form>`
//! Prints the generated `.ig` module to stdout (feed it to `igc compile`), or the desugar error to
//! stderr with exit code 1.

use std::process::exit;

fn main() {
    let path = std::env::args().nth(1).unwrap_or_else(|| {
        eprintln!("usage: desugar <file.form>");
        exit(2);
    });
    let src = std::fs::read_to_string(&path).unwrap_or_else(|e| {
        eprintln!("cannot read {path}: {e}");
        exit(2);
    });
    match igniter_frame::igv_desugar::desugar(&src) {
        Ok(ig) => print!("{ig}"),
        Err(e) => {
            eprintln!("desugar error (line {}): {}", e.line, e.msg);
            exit(1);
        }
    }
}
