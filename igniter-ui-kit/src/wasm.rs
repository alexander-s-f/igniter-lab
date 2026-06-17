//! WASM bindings for the form runtime (LAB-FRAME-UI-KIT-FORMS-P9). A thin `#[wasm_bindgen]` wrapper
//! over `FormRuntime` (the Lead Intake form): the browser calls `new` / `click` / `key` /
//! `backspace` / `render_svg` / `frame_index` / `render_digest` / `lineage_json` / `reset`. The host
//! catches DOM pointer + keyboard events but only ROUTES them; layout, hit-test, intent routing,
//! field state, and validation all run in Rust.

use crate::binding::{BoundViewHost, FixtureContractRegistry};
use crate::composition::WorkbenchRuntime;
use crate::FormRuntime;
use wasm_bindgen::prelude::*;

/// A workbench bound to FIXTURE `.ig` contracts (LAB-FRAME-IG-BINDING-P16). The browser fetches a
/// bound ViewArtifact, calls `from_artifact`, and interacts; submit routes through the fixture host
/// (validate → scoped errors, or a deterministic fixture receipt). No machine, no authority in the
/// browser — the fixture registry is deterministic and authority-free.
#[wasm_bindgen]
pub struct WasmBoundHost {
    inner: BoundViewHost,
}

#[wasm_bindgen]
impl WasmBoundHost {
    pub fn from_artifact(json: &str) -> Result<WasmBoundHost, String> {
        BoundViewHost::from_artifact(json, FixtureContractRegistry::lead_review())
            .map(|inner| WasmBoundHost { inner })
            .map_err(|e| e.to_string())
    }
    pub fn click(&mut self, cx: f64, cy: f64) -> bool {
        self.inner.click(cx, cy)
    }
    pub fn key(&mut self, ch: &str) -> bool {
        self.inner.key(ch)
    }
    pub fn render_svg(&self) -> String {
        self.inner.render_svg()
    }
    pub fn selected_lead(&self) -> String {
        self.inner.selected_lead()
    }
    pub fn last_receipt_id(&self) -> Option<String> {
        self.inner.last_receipt().map(|r| r.id.clone())
    }
    pub fn last_refusal(&self) -> Option<String> {
        self.inner.last_refusal().map(String::from)
    }
    pub fn calls(&self, contract: &str) -> usize {
        self.inner.calls(contract)
    }
}

/// The composable Lead Review workbench (LAB-FRAME-UI-KIT-COMPOSITION-P10).
#[wasm_bindgen]
pub struct WasmWorkbench {
    inner: WorkbenchRuntime,
}

#[wasm_bindgen]
impl WasmWorkbench {
    #[wasm_bindgen(constructor)]
    pub fn new() -> WasmWorkbench {
        WasmWorkbench { inner: WorkbenchRuntime::lead_review() }
    }

    /// Compile a `workbench` ViewArtifact JSON into a live runtime (LAB-FRAME-VIEWARTIFACT-P12).
    /// Errors surface as a thrown JS string. The browser fetches the .json and calls this — the
    /// authoring layer is portable data, not Rust.
    pub fn from_artifact(json: &str) -> Result<WasmWorkbench, String> {
        WorkbenchRuntime::from_artifact(json).map(|inner| WasmWorkbench { inner }).map_err(|e| e.to_string())
    }
    pub fn click(&mut self, css_x: f64, css_y: f64) -> bool {
        self.inner.click(css_x, css_y)
    }
    pub fn key(&mut self, ch: &str) -> bool {
        self.inner.key(ch)
    }
    pub fn backspace(&mut self) -> bool {
        self.inner.backspace()
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

impl Default for WasmWorkbench {
    fn default() -> Self {
        Self::new()
    }
}

#[wasm_bindgen]
pub struct WasmForm {
    inner: FormRuntime,
}

#[wasm_bindgen]
impl WasmForm {
    #[wasm_bindgen(constructor)]
    pub fn new() -> WasmForm {
        WasmForm { inner: FormRuntime::lead_intake() }
    }

    pub fn click(&mut self, css_x: f64, css_y: f64) -> bool {
        self.inner.click(css_x, css_y)
    }

    /// Route a typed character to the focused field. Returns `true` iff state changed.
    pub fn key(&mut self, ch: &str) -> bool {
        self.inner.key(ch)
    }

    pub fn backspace(&mut self) -> bool {
        self.inner.backspace()
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

impl Default for WasmForm {
    fn default() -> Self {
        Self::new()
    }
}
