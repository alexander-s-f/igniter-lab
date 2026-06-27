//! LAB-FRAME-LAYOUT-VOCAB-P8 — ONE generic widget render host, shared by every screen.
//!
//! Until now each screen (list / table / form / text / scroll) shipped its own `RenderHost` with an
//! ad-hoc `kind` vocabulary. This module replaces all five with a single `WidgetRenderHost`
//! parameterised only by canvas size: it renders a frame by dispatching on each node's CANONICAL
//! `data.kind` + a small, documented data contract. A new screen no longer writes a render host — it
//! emits canonical widget nodes and gets a consistent look for free. This canonical vocabulary is
//! also the surface a developer authors against (the seam toward `.igv`).
//!
//! ## Canonical widget vocabulary (`data.kind` → contract)
//! - `title`        `{label}`                                   — bold heading
//! - `label`        `{label, tone?:"dim"}`                      — field/inline label
//! - `note`         `{label, tone?:"dim"|"ok"|"warn", align?:"end"}` — small annotation (hint/status/footer)
//! - `panel`        `{label?, variant?:"surface"|"bar"|"group"}` — bordered container
//! - `row`          `{label?, selected?, hovered?, focused?, done?, lead?:"dot"}` — list/table row
//! - `cell`         `{label, hot?}`                             — table data cell
//! - `header_cell`  `{label}`                                   — table header cell
//! - `button`       `{label, tone?:"go"|"warn"|"neutral"|"add"}` — pressable
//! - `toggle`       `{on}`                                      — on/off switch
//! - `checkbox`     `{on}`
//! - `segment`      `{label, selected}`                         — one cell of a segmented control
//! - `stepper_btn`  `{glyph}` · `stepper_val` `{label}`
//! - `input`        `{value, placeholder, focused}`             — text field
//! - `scrollbar`    `{variant:"track"|"thumb"}`

use crate::{Frame, RenderHost};

fn esc(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;")
}

/// The single render host. Construct with the screen's canvas size; everything else comes from each
/// node's canonical `kind` + data.
pub struct WidgetRenderHost {
    pub width: i64,
    pub height: i64,
}

impl WidgetRenderHost {
    pub fn new(width: i64, height: i64) -> Self {
        Self { width, height }
    }
}

impl RenderHost for WidgetRenderHost {
    fn render(&self, frame: &Frame) -> String {
        let mut b = String::new();
        for n in &frame.nodes {
            let (x, y, w, h) = (n.sx, n.sy, n.sw.unwrap_or(0), n.sh.unwrap_or(0));
            let d = &n.data;
            let kind = d.get("kind").and_then(|v| v.as_str()).unwrap_or("");
            let lbl = d.get("label").and_then(|v| v.as_str()).unwrap_or("");
            let flag = |k: &str| d.get(k).and_then(|v| v.as_bool()).unwrap_or(false);
            let cy = y + h / 2;
            match kind {
                "title" => b.push_str(&format!(
                    "  <text x=\"{x}\" y=\"{}\" font-family=\"monospace\" font-size=\"16\" font-weight=\"bold\" fill=\"#e6edf3\">{}</text>\n",
                    y + 20, esc(lbl)
                )),
                "label" => {
                    let col = if d.get("tone").and_then(|t| t.as_str()) == Some("dim") { "#8b949e" } else { "#c9d1d9" };
                    b.push_str(&format!("  <text x=\"{x}\" y=\"{}\" font-family=\"monospace\" font-size=\"13\" fill=\"{col}\">{}</text>\n", cy + 5, esc(lbl)));
                }
                "note" => {
                    let col = match d.get("tone").and_then(|t| t.as_str()) {
                        Some("ok") => "#3fb950",
                        Some("warn") => "#d29922",
                        _ => "#8b949e",
                    };
                    if d.get("align").and_then(|a| a.as_str()) == Some("end") {
                        b.push_str(&format!("  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"12\" fill=\"{col}\" text-anchor=\"end\">{}</text>\n", x + w, cy + 4, esc(lbl)));
                    } else {
                        b.push_str(&format!("  <text x=\"{x}\" y=\"{}\" font-family=\"monospace\" font-size=\"12\" fill=\"{col}\">{}</text>\n", cy + 4, esc(lbl)));
                    }
                }
                "panel" => {
                    let (fill, stroke, rx) = match d.get("variant").and_then(|v| v.as_str()) {
                        Some("bar") => ("#161b22", "#30363d", 6),
                        Some("group") => ("#0d1117", "#30363d", 7),
                        _ => ("#0d1117", "#30363d", 8),
                    };
                    b.push_str(&format!("  <rect x=\"{x}\" y=\"{y}\" width=\"{w}\" height=\"{h}\" rx=\"{rx}\" fill=\"{fill}\" stroke=\"{stroke}\"/>\n"));
                    if !lbl.is_empty() {
                        b.push_str(&format!("  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"12\" font-weight=\"bold\" fill=\"#8b949e\">{}</text>\n", x + 14, y + 22, esc(lbl)));
                    }
                }
                "row" => {
                    let (sel, hov, foc) = (flag("selected"), flag("hovered"), flag("focused"));
                    let fill = if sel { "#16304f" } else if hov { "#161b22" } else { "#0d1117" };
                    let (ix, iy, iw, ih) = (x + 2, y + 2, (w - 4).max(0), (h - 4).max(0));
                    b.push_str(&format!("  <rect x=\"{ix}\" y=\"{iy}\" width=\"{iw}\" height=\"{ih}\" rx=\"6\" fill=\"{fill}\" stroke=\"#21262d\"/>\n"));
                    if foc {
                        b.push_str(&format!("  <rect x=\"{ix}\" y=\"{iy}\" width=\"{iw}\" height=\"{ih}\" rx=\"6\" fill=\"none\" stroke=\"#1f6feb\" stroke-width=\"2\"/>\n"));
                    }
                    // leading marker: a done-check, a dot, or nothing
                    let mut tx = x + 14;
                    let mut lbl_col = "#c9d1d9";
                    if let Some(done) = d.get("done").and_then(|v| v.as_bool()) {
                        let (g, col) = if done { ("✓", "#3fb950") } else { ("○", "#8b949e") };
                        b.push_str(&format!("  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"13\" fill=\"{col}\">{g}</text>\n", x + 12, cy + 5));
                        tx = x + 30;
                        if done { lbl_col = "#3fb950"; }
                    } else if d.get("lead").and_then(|v| v.as_str()) == Some("dot") {
                        let col = if sel { "#3fb950" } else { "#484f58" };
                        b.push_str(&format!("  <circle cx=\"{}\" cy=\"{cy}\" r=\"3\" fill=\"{col}\"/>\n", x + 14));
                        tx = x + 28;
                    }
                    if !lbl.is_empty() {
                        b.push_str(&format!("  <text x=\"{tx}\" y=\"{}\" font-family=\"monospace\" font-size=\"13\" fill=\"{lbl_col}\">{}</text>\n", cy + 5, esc(lbl)));
                    }
                }
                "cell" => {
                    let col = if flag("hot") { "#3fb950" } else { "#c9d1d9" };
                    b.push_str(&format!("  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"13\" fill=\"{col}\">{}</text>\n", x + 10, cy + 5, esc(lbl)));
                }
                "header_cell" => b.push_str(&format!("  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"12\" font-weight=\"bold\" fill=\"#8b949e\">{}</text>\n", x + 10, cy + 4, esc(lbl))),
                "button" => {
                    let (fill, stroke, dash, tcol) = match d.get("tone").and_then(|t| t.as_str()) {
                        Some("go") => ("#238636", "#2ea043", "", "#f0f6fc"),
                        Some("warn") => ("#161b22", "#d29922", "", "#f0f6fc"),
                        Some("add") => ("#161b22", "#2ea043", " stroke-dasharray=\"4 3\"", "#3fb950"),
                        _ => ("#21262d", "#30363d", "", "#f0f6fc"),
                    };
                    b.push_str(&format!("  <rect x=\"{x}\" y=\"{y}\" width=\"{w}\" height=\"{h}\" rx=\"8\" fill=\"{fill}\" stroke=\"{stroke}\"{dash}/>\n"));
                    b.push_str(&format!("  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"14\" fill=\"{tcol}\" text-anchor=\"middle\">{}</text>\n", x + w / 2, cy + 5, esc(lbl)));
                }
                "toggle" => {
                    let on = flag("on");
                    let track = if on { "#238636" } else { "#30363d" };
                    let knob_x = if on { x + w - h } else { x };
                    b.push_str(&format!("  <rect x=\"{x}\" y=\"{y}\" width=\"{w}\" height=\"{h}\" rx=\"{}\" fill=\"{track}\"/>\n", h / 2));
                    b.push_str(&format!("  <circle cx=\"{}\" cy=\"{cy}\" r=\"{}\" fill=\"#f0f6fc\"/>\n", knob_x + h / 2, h / 2 - 3));
                }
                "checkbox" => {
                    let on = flag("on");
                    let fill = if on { "#238636" } else { "#0d1117" };
                    b.push_str(&format!("  <rect x=\"{x}\" y=\"{y}\" width=\"{w}\" height=\"{h}\" rx=\"5\" fill=\"{fill}\" stroke=\"#30363d\"/>\n"));
                    if on {
                        b.push_str(&format!("  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"15\" fill=\"#f0f6fc\" text-anchor=\"middle\">✓</text>\n", x + w / 2, cy + 5));
                    }
                }
                "segment" => {
                    if flag("selected") {
                        b.push_str(&format!("  <rect x=\"{}\" y=\"{}\" width=\"{}\" height=\"{}\" rx=\"6\" fill=\"#1f6feb\"/>\n", x + 2, y + 2, (w - 4).max(0), (h - 4).max(0)));
                    }
                    let col = if flag("selected") { "#f0f6fc" } else { "#8b949e" };
                    b.push_str(&format!("  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"13\" fill=\"{col}\" text-anchor=\"middle\">{}</text>\n", x + w / 2, cy + 5, esc(lbl)));
                }
                "stepper_btn" => {
                    let g = d.get("glyph").and_then(|v| v.as_str()).unwrap_or("");
                    b.push_str(&format!("  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"18\" fill=\"#58a6ff\" text-anchor=\"middle\">{}</text>\n", x + w / 2, cy + 6, esc(g)));
                }
                "stepper_val" => b.push_str(&format!("  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"15\" fill=\"#e6edf3\" text-anchor=\"middle\">{}</text>\n", x + w / 2, cy + 5, esc(lbl))),
                "input" => {
                    let focused = flag("focused");
                    let val = d.get("value").and_then(|v| v.as_str()).unwrap_or("");
                    let stroke = if focused { "#1f6feb" } else { "#30363d" };
                    b.push_str(&format!("  <rect x=\"{x}\" y=\"{y}\" width=\"{w}\" height=\"{h}\" rx=\"6\" fill=\"#0d1117\" stroke=\"{stroke}\"/>\n"));
                    if val.is_empty() && !focused {
                        let ph = d.get("placeholder").and_then(|v| v.as_str()).unwrap_or("");
                        b.push_str(&format!("  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"13\" fill=\"#484f58\">{}</text>\n", x + 10, y + 22, esc(ph)));
                    } else {
                        let caret = if focused { "▏" } else { "" };
                        b.push_str(&format!("  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"13\" fill=\"#e6edf3\">{}{caret}</text>\n", x + 10, y + 22, esc(val)));
                    }
                }
                "scrollbar" => {
                    let fill = if d.get("variant").and_then(|v| v.as_str()) == Some("thumb") { "#30363d" } else { "#0d1117" };
                    b.push_str(&format!("  <rect x=\"{x}\" y=\"{y}\" width=\"{w}\" height=\"{h}\" rx=\"4\" fill=\"{fill}\"/>\n"));
                }
                _ => {}
            }
        }
        format!(
            "<svg viewBox=\"0 0 {w} {h}\" xmlns=\"http://www.w3.org/2000/svg\">\n  <rect width=\"{w}\" height=\"{h}\" fill=\"#010409\"/>\n{b}</svg>\n",
            w = self.width,
            h = self.height
        )
    }
}
