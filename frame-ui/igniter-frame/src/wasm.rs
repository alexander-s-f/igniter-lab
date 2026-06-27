//! WASM bindings (LAB-FRAME-WASM-LIVE-STEP-P5). A THIN `#[wasm_bindgen]` wrapper over the
//! synchronous `FrameRuntime`: the browser calls `new` / `render_svg` / `click` / `frame_index` /
//! `lineage_json` / `render_digest` / `reset`. ALL logic (hit-test → intent → effect →
//! re-projection) is in Rust; the JS host only renders the returned SVG and forwards pointer
//! coordinates. Compiles to `wasm32-unknown-unknown` WITHOUT `igniter-machine`.
//!
//! Build proof: `cargo build --target wasm32-unknown-unknown --no-default-features --features wasm`.

use crate::runtime::FrameRuntime;
use wasm_bindgen::prelude::*;

/// The live frame runtime exposed to the browser. One instance == one interactive scene.
#[wasm_bindgen]
pub struct WasmRuntime {
    inner: FrameRuntime,
}

#[wasm_bindgen]
impl WasmRuntime {
    /// Initialise the demo scene (a clickable entity between two static posts).
    #[wasm_bindgen(constructor)]
    pub fn new() -> WasmRuntime {
        WasmRuntime {
            inner: FrameRuntime::demo(),
        }
    }

    /// Render the CURRENT frame to an SVG string (the host draws this verbatim).
    pub fn render_svg(&self) -> String {
        self.inner.render_svg()
    }

    /// Forward a real pointer click (CSS coords). Returns `true` iff it produced a state effect.
    /// The host computes no intent — this call runs the whole loop in Rust.
    pub fn click(&mut self, css_x: f64, css_y: f64) -> bool {
        self.inner.click(css_x, css_y)
    }

    /// The current frame index (step counter).
    pub fn frame_index(&self) -> u32 {
        self.inner.frame_index() as u32
    }

    /// The render digest of the current frame (host-agnostic; same bytes ⇒ same pixels).
    pub fn render_digest(&self) -> String {
        self.inner.render_digest()
    }

    /// Lineage of the current state as JSON: `{input_receipt_id, effect_receipt_id, frame_index}`.
    pub fn lineage_json(&self) -> String {
        self.inner.lineage_json()
    }

    /// Reset to the initial demo scene (for replaying a captured click log).
    pub fn reset(&mut self) {
        self.inner = FrameRuntime::demo();
    }
}

impl Default for WasmRuntime {
    fn default() -> Self {
        Self::new()
    }
}

/// LAB-FRAME-LAYOUT-VOCAB-P2 — the declarative list/detail screen exposed to the browser. A thin
/// wrapper over `ListScreenRuntime`: the whole screen is composed from `layout` boxes and `solve`d
/// in Rust; the JS host only draws the SVG and forwards pointer coords. Click a row to select, the
/// ＋ row to add (the list auto-flows), the detail button to toggle done.
#[wasm_bindgen]
pub struct WasmListScreen {
    inner: crate::list_screen::ListScreenRuntime,
}

#[wasm_bindgen]
impl WasmListScreen {
    #[wasm_bindgen(constructor)]
    pub fn new() -> WasmListScreen {
        WasmListScreen {
            inner: crate::list_screen::ListScreenRuntime::new(),
        }
    }

    pub fn render_svg(&self) -> String {
        self.inner.render_svg()
    }

    pub fn click(&mut self, css_x: f64, css_y: f64) -> bool {
        self.inner.click(css_x, css_y)
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

impl Default for WasmListScreen {
    fn default() -> Self {
        Self::new()
    }
}

/// LAB-FRAME-LAYOUT-VOCAB-P3 — the data-bound TABLE screen exposed to the browser. Composed on the
/// `layout::table` primitive: columns auto-align across rows. Click a cell to select its row; the
/// controls cycle the selected lead's stage, toggle its hot flag, or add a row (the table flows).
#[wasm_bindgen]
pub struct WasmTableScreen {
    inner: crate::table_screen::TableScreenRuntime,
}

#[wasm_bindgen]
impl WasmTableScreen {
    #[wasm_bindgen(constructor)]
    pub fn new() -> WasmTableScreen {
        WasmTableScreen {
            inner: crate::table_screen::TableScreenRuntime::new(),
        }
    }

    pub fn render_svg(&self) -> String {
        self.inner.render_svg()
    }

    pub fn click(&mut self, css_x: f64, css_y: f64) -> bool {
        self.inner.click(css_x, css_y)
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

impl Default for WasmTableScreen {
    fn default() -> Self {
        Self::new()
    }
}

/// LAB-FRAME-LAYOUT-VOCAB-P5 — the settings FORM exposed to the browser. Broadens the widget
/// vocabulary (toggles, checkbox, segmented control, stepper, buttons) over the cross-aligned layout;
/// click-driven, deterministic, machine-free.
#[wasm_bindgen]
pub struct WasmFormScreen {
    inner: crate::form_screen::FormScreenRuntime,
}

#[wasm_bindgen]
impl WasmFormScreen {
    #[wasm_bindgen(constructor)]
    pub fn new() -> WasmFormScreen {
        WasmFormScreen {
            inner: crate::form_screen::FormScreenRuntime::new(),
        }
    }

    pub fn render_svg(&self) -> String {
        self.inner.render_svg()
    }

    pub fn click(&mut self, css_x: f64, css_y: f64) -> bool {
        self.inner.click(css_x, css_y)
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

impl Default for WasmFormScreen {
    fn default() -> Self {
        Self::new()
    }
}

/// LAB-FRAME-LAYOUT-VOCAB-P6 — the keyboard TEXT-ENTRY contact form exposed to the browser. Click an
/// input to focus it, then type; `Backspace` deletes, `Enter` submits. The page forwards `keydown`
/// to `key`; pointer to `click`. Deterministic, machine-free.
#[wasm_bindgen]
pub struct WasmTextForm {
    inner: crate::text_form_screen::TextFormRuntime,
}

#[wasm_bindgen]
impl WasmTextForm {
    #[wasm_bindgen(constructor)]
    pub fn new() -> WasmTextForm {
        WasmTextForm {
            inner: crate::text_form_screen::TextFormRuntime::new(),
        }
    }

    pub fn render_svg(&self) -> String {
        self.inner.render_svg()
    }

    pub fn click(&mut self, css_x: f64, css_y: f64) -> bool {
        self.inner.click(css_x, css_y)
    }

    /// Route a browser key (e.g. `e.key`) into the focused field. Returns `true` iff state changed.
    pub fn key(&mut self, k: &str) -> bool {
        self.inner.key(k)
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

impl Default for WasmTextForm {
    fn default() -> Self {
        Self::new()
    }
}

/// LAB-FRAME-LAYOUT-VOCAB-P7 — the scrollable list (scroll/overflow + keyboard nav + hover) exposed
/// to the browser. The page forwards `wheel` → `scroll`, `pointermove` → `hover`, `keydown` → `key`,
/// pointer → `click`. Hover/scroll are view-only (no frame-index bump); nav/select advance the frame.
#[wasm_bindgen]
pub struct WasmScrollList {
    inner: crate::scroll_list_screen::ScrollListRuntime,
}

#[wasm_bindgen]
impl WasmScrollList {
    #[wasm_bindgen(constructor)]
    pub fn new() -> WasmScrollList {
        WasmScrollList {
            inner: crate::scroll_list_screen::ScrollListRuntime::new(),
        }
    }

    pub fn render_svg(&self) -> String {
        self.inner.render_svg()
    }

    pub fn click(&mut self, css_x: f64, css_y: f64) -> bool {
        self.inner.click(css_x, css_y)
    }

    pub fn hover(&mut self, css_x: f64, css_y: f64) -> bool {
        self.inner.hover(css_x, css_y)
    }

    pub fn scroll(&mut self, css_x: f64, css_y: f64, dy: f64) -> bool {
        self.inner.scroll(css_x, css_y, dy)
    }

    pub fn key(&mut self, k: &str, shift: bool) -> bool {
        self.inner.key(k, shift)
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

impl Default for WasmScrollList {
    fn default() -> Self {
        Self::new()
    }
}

/// LAB-FRAME-DX-VIEW-D host bridge — render an `.ig`-authored `Element` tree (JSON) through the
/// frame-ui pipeline (layout → solve → canonical widgets → shared host). Closes the loop: a view
/// authored as pure igniter element-contracts renders live, machine-free, in the browser.
#[wasm_bindgen]
pub fn render_ig_view(element_json: &str, w: i32, h: i32) -> String {
    crate::ig_bridge::render_ig_view(element_json, w as i64, h as i64)
}

/// LAB-FRAME-LAYOUT-VOCAB-P4 — author a layout as TEXT, see it solved live. Parses the layout DSL and
/// returns an inspection SVG of the solved boxes; on a parse error returns an SVG card naming the
/// 1-based line and message. Pure + total — safe to call on every keystroke from a text field.
#[wasm_bindgen]
pub fn layout_preview(src: &str, w: i32, h: i32) -> String {
    match crate::layout::parse(src) {
        Ok(tree) => crate::layout::preview_svg(&tree, w as i64, h as i64),
        Err(e) => crate::layout::error_svg(&e, w as i64, h as i64),
    }
}
