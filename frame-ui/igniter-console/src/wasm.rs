//! WASM bindings for the console (LAB-FRAME-APP-CONSOLE-P13). The browser fetches a ViewArtifact
//! JSON, calls `WasmConsole.from_artifact`, then maps DOM events to console API calls. All logic
//! (target runtime, recording, time-travel, diff) is in Rust.

use crate::Console;
use wasm_bindgen::prelude::*;

#[wasm_bindgen]
pub struct WasmConsole {
    inner: Console,
}

#[wasm_bindgen]
impl WasmConsole {
    /// Build a console around a ViewArtifact-authored workbench. Errors throw a JS string.
    pub fn from_artifact(json: &str) -> Result<WasmConsole, String> {
        Console::from_artifact(json).map(|inner| WasmConsole { inner }).map_err(|e| e.to_string())
    }

    /// Route a console-space pointer click (strip chip → scrub; viewer → forward to the target).
    pub fn click(&mut self, cx: f64, cy: f64) -> bool {
        self.inner.click(cx, cy)
    }
    pub fn key(&mut self, ch: &str) {
        self.inner.key(ch)
    }
    pub fn backspace(&mut self) {
        self.inner.backspace()
    }
    pub fn select_step(&mut self, i: usize) {
        self.inner.select_step(i)
    }

    /// Attach a host action/receipt record (JSON, plain data) to the latest frame. The host produces
    /// it elsewhere (P17/P18 bridges); the console only renders + time-travels it.
    pub fn attach_action(&mut self, json: &str) -> bool {
        self.inner.attach_action_json(json)
    }

    pub fn render_svg(&self) -> String {
        self.inner.render_svg()
    }
    pub fn len(&self) -> usize {
        self.inner.len()
    }
    pub fn selected(&self) -> usize {
        self.inner.selected()
    }
    pub fn is_live(&self) -> bool {
        self.inner.is_live()
    }
    pub fn lineage_json(&self) -> String {
        self.inner.lineage_json()
    }
    pub fn diff_json(&self) -> String {
        self.inner.diff_json()
    }
    pub fn selected_render_digest(&self) -> String {
        self.inner.selected_render_digest()
    }
}
