//! WASM bindings for the GUI runtime (LAB-FRAME-GUI-ENGINE-REHOME-P8). A thin `#[wasm_bindgen]`
//! wrapper over `GuiRuntime`: the browser calls `new` / `click` / `render_svg` / `frame_index` /
//! `render_digest` / `lineage_json` / `reset`. Layout, hit-test, intent, and the update reducer all
//! run in Rust; the JS host only maps the pointer and draws the returned SVG.

use crate::GuiRuntime;
use wasm_bindgen::prelude::*;

#[wasm_bindgen]
pub struct WasmGui {
    inner: GuiRuntime,
}

#[wasm_bindgen]
impl WasmGui {
    #[wasm_bindgen(constructor)]
    pub fn new() -> WasmGui {
        WasmGui {
            inner: GuiRuntime::new(),
        }
    }

    /// Forward a real pointer click (CSS coords). Returns `true` iff a widget intent fired.
    pub fn click(&mut self, css_x: f64, css_y: f64) -> bool {
        self.inner.click(css_x, css_y)
    }

    pub fn render_svg(&self) -> String {
        self.inner.render_svg()
    }

    pub fn frame_index(&self) -> u32 {
        self.inner.frame_index() as u32
    }

    pub fn render_digest(&self) -> String {
        self.inner.render_digest()
    }

    pub fn lineage_json(&self) -> String {
        self.inner.lineage_json()
    }

    pub fn reset(&mut self) {
        self.inner.reset();
    }
}

impl Default for WasmGui {
    fn default() -> Self {
        Self::new()
    }
}
