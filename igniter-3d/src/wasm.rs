//! WASM bindings for the 3D runtime (LAB-FRAME-3D-POC-REHOME-P7). A thin `#[wasm_bindgen]` wrapper
//! over `Cube3dRuntime`: the browser calls `new` / `tick` / `render_svg` / `frame_index` /
//! `render_digest` / `lineage_json` / `reset`. ALL the 3D math (rotation, perspective projection,
//! wireframe) is in Rust; the JS host only renders the returned SVG and drives the tick.
//!
//! Build proof: `cargo build --target wasm32-unknown-unknown --features wasm` (no `igniter-machine`).

use crate::Cube3dRuntime;
use wasm_bindgen::prelude::*;

#[wasm_bindgen]
pub struct WasmCube3d {
    inner: Cube3dRuntime,
}

#[wasm_bindgen]
impl WasmCube3d {
    #[wasm_bindgen(constructor)]
    pub fn new() -> WasmCube3d {
        WasmCube3d { inner: Cube3dRuntime::new() }
    }

    /// Advance the world one tick (rotate the cube). Returns `true`.
    pub fn tick(&mut self) -> bool {
        self.inner.tick()
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

impl Default for WasmCube3d {
    fn default() -> Self {
        Self::new()
    }
}
