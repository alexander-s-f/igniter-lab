//! Deterministic integer box layout (LAB-FRAME-LAYOUT-VOCAB-P1).
//!
//! The frame-ui projectors today hand-compute every `(x, y, w, h)` with screen-specific integer
//! constants (`MARGIN`/`GAP`/column tuples). Every new screen therefore needs a fresh Rust
//! projector with hand-tuned math — the #1 DX tax of the stack. This module replaces that with a
//! **composable, recursive, pure-integer layout pass**: describe a screen as a tree of nested
//! `Row`/`Col` boxes with fixed-or-flex sizes, and `solve` computes absolute integer rects for the
//! whole tree.
//!
//! It is deterministic and machine-free by construction — only integer arithmetic, no `f64`, no
//! clock/RNG, no kernel — so it composes cleanly with the stack's content-addressed frame digests
//! (`cargo build --no-default-features` compiles it with zero `igniter-machine` dependency). The
//! same flexbox-lite model expresses a list (a `Col` of rows), a 3-column workbench (a `Row` of
//! `Col` panels), a table (a `Col` of rows, each a `Row` of cells), and arbitrary nesting — by
//! *composing boxes*, not by writing a projector.

/// How a box arranges its children along its MAIN axis.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Dir {
    /// Children stacked top→bottom; main axis = vertical (`y`/`height`).
    Col,
    /// Children laid left→right; main axis = horizontal (`x`/`width`).
    Row,
}

/// A box's size along its PARENT's main axis.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Size {
    /// Exact main-axis size in integer pixels.
    Fixed(i64),
    /// Share the remaining main-axis space proportionally to `weight` (clamped to ≥ 1). Leftover
    /// pixels after integer division are distributed one-each to the earliest flex siblings, so the
    /// result is exact (children always fill the content box) and order-deterministic.
    Flex(i64),
}

/// A box's size along its parent's CROSS axis (perpendicular to the parent's main axis). `Stretch`
/// (the default) fills the parent's cross content extent; `Fixed(n)` takes exactly `n` px and is then
/// positioned by the parent's [`Align`]. (True size-to-content/intrinsic sizing needs text metrics —
/// out of scope for the machine-free engine; author the cross size explicitly with `Fixed`.)
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CrossSize {
    Stretch,
    Fixed(i64),
}

/// Where a container places a child that is NOT cross-stretched (`CrossSize::Fixed`) along the cross
/// axis — the layout analogue of CSS `align-items`. Stretched children ignore this (they fill).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Align {
    Start,
    Center,
    End,
}

/// A node in the layout tree. The MAIN axis (`dir`) uses fixed/flex sizing; the CROSS axis defaults
/// to stretch but a child may take a fixed cross size (`cross`) and be positioned by its parent's
/// `align` — a deterministic flexbox subset.
#[derive(Clone, Debug)]
pub struct LayoutBox {
    pub id: String,
    /// How THIS box arranges its own children (ignored for a leaf).
    pub dir: Dir,
    /// This box's size along its parent's main axis.
    pub main: Size,
    /// This box's size along its parent's cross axis (`Stretch` by default).
    pub cross: CrossSize,
    /// How THIS box positions its non-stretched children on the cross axis (`Start` by default).
    pub align: Align,
    /// Uniform inner padding (insets the content box on all four sides).
    pub pad: i64,
    /// Gap inserted between adjacent children along the main axis.
    pub gap: i64,
    pub children: Vec<LayoutBox>,
}

impl LayoutBox {
    /// A leaf box (no children) of a fixed main-axis size.
    pub fn leaf(id: impl Into<String>, main: Size) -> Self {
        Self {
            id: id.into(),
            dir: Dir::Col,
            main,
            cross: CrossSize::Stretch,
            align: Align::Start,
            pad: 0,
            gap: 0,
            children: Vec::new(),
        }
    }

    /// A vertical container (children stacked top→bottom).
    pub fn col(id: impl Into<String>, main: Size, children: Vec<LayoutBox>) -> Self {
        Self {
            id: id.into(),
            dir: Dir::Col,
            main,
            cross: CrossSize::Stretch,
            align: Align::Start,
            pad: 0,
            gap: 0,
            children,
        }
    }

    /// A horizontal container (children left→right).
    pub fn row(id: impl Into<String>, main: Size, children: Vec<LayoutBox>) -> Self {
        Self {
            id: id.into(),
            dir: Dir::Row,
            main,
            cross: CrossSize::Stretch,
            align: Align::Start,
            pad: 0,
            gap: 0,
            children,
        }
    }

    /// Builder: set uniform inner padding.
    pub fn pad(mut self, pad: i64) -> Self {
        self.pad = pad.max(0);
        self
    }

    /// Builder: set the gap between children.
    pub fn gap(mut self, gap: i64) -> Self {
        self.gap = gap.max(0);
        self
    }

    /// Builder: take a fixed cross-axis size (instead of stretching to fill the parent cross extent).
    pub fn cross(mut self, n: i64) -> Self {
        self.cross = CrossSize::Fixed(n.max(0));
        self
    }

    /// Builder: set how this box positions its non-stretched children on the cross axis.
    pub fn align(mut self, align: Align) -> Self {
        self.align = align;
        self
    }
}

/// A solved absolute rectangle for one box, in integer screen coordinates. Emitted parent-before-
/// children (pre-order), which matches the projectors' "background panel first, then its children"
/// order and the runtime's innermost-smallest-area hit-test.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Rect {
    pub id: String,
    pub x: i64,
    pub y: i64,
    pub w: i64,
    pub h: i64,
}

/// Solve a layout tree into absolute integer rects within the box `(x, y, w, h)`. Pure and total:
/// negative/over-padded extents clamp to `0` (no panic, no overflow — arithmetic is saturating).
pub fn solve(root: &LayoutBox, x: i64, y: i64, w: i64, h: i64) -> Vec<Rect> {
    let mut out = Vec::new();
    place(root, x, y, w.max(0), h.max(0), &mut out);
    out
}

fn place(b: &LayoutBox, x: i64, y: i64, w: i64, h: i64, out: &mut Vec<Rect>) {
    out.push(Rect {
        id: b.id.clone(),
        x,
        y,
        w,
        h,
    });
    if b.children.is_empty() {
        return;
    }

    // content box (inset by padding, clamped non-negative)
    let cx = x + b.pad;
    let cy = y + b.pad;
    let cw = (w - 2 * b.pad).max(0);
    let ch = (h - 2 * b.pad).max(0);

    let n = b.children.len() as i64;
    let total_gap = b.gap.saturating_mul(n - 1).max(0);
    // available main-axis length for the children themselves (after gaps)
    let main_avail = (if b.dir == Dir::Col { ch } else { cw } - total_gap).max(0);
    let cross = if b.dir == Dir::Col { cw } else { ch };

    let mains = distribute(&b.children, main_avail);

    let mut offset = if b.dir == Dir::Col { cy } else { cx };
    for (child, main) in b.children.iter().zip(mains) {
        // cross-axis size: stretch fills the parent cross content; fixed clamps into it
        let child_cross = match child.cross {
            CrossSize::Stretch => cross,
            CrossSize::Fixed(n) => n.clamp(0, cross),
        };
        // cross-axis offset within the parent cross content (stretched children sit at the start)
        let cross_off = match child.cross {
            CrossSize::Stretch => 0,
            CrossSize::Fixed(_) => match b.align {
                Align::Start => 0,
                Align::Center => (cross - child_cross) / 2,
                Align::End => cross - child_cross,
            }
            .max(0),
        };
        let (rx, ry, rw, rh) = if b.dir == Dir::Col {
            (cx + cross_off, offset, child_cross, main)
        } else {
            (offset, cy + cross_off, main, child_cross)
        };
        place(child, rx, ry, rw, rh, out);
        offset += main + b.gap;
    }
}

/// Resolve each child's main-axis size: fixed children take their size; flex children share the
/// space remaining after fixed (and gaps, already removed from `main_avail`) by weight, with the
/// integer-division remainder distributed one-each to the earliest flex children. The sum of the
/// returned sizes equals `main_avail` whenever any flex child exists (exact fill).
fn distribute(children: &[LayoutBox], main_avail: i64) -> Vec<i64> {
    let mut sizes = vec![0i64; children.len()];
    let mut fixed_sum = 0i64;
    let mut total_weight = 0i64;
    for c in children {
        match c.main {
            Size::Fixed(s) => fixed_sum += s.max(0),
            Size::Flex(wt) => total_weight += wt.max(1),
        }
    }

    if total_weight == 0 {
        // all fixed → take sizes as-is (may under/overflow the container; deterministic either way)
        for (i, c) in children.iter().enumerate() {
            if let Size::Fixed(s) = c.main {
                sizes[i] = s.max(0);
            }
        }
        return sizes;
    }

    let remaining = (main_avail - fixed_sum).max(0);
    let unit = remaining / total_weight;
    let mut leftover = remaining - unit * total_weight; // 0..total_weight
    for (i, c) in children.iter().enumerate() {
        match c.main {
            Size::Fixed(s) => sizes[i] = s.max(0),
            Size::Flex(wt) => {
                let wt = wt.max(1);
                let mut s = unit * wt;
                // hand the integer-division remainder to the earliest flex children, one px each
                let take = leftover.min(wt);
                s += take;
                leftover -= take;
                sizes[i] = s;
            }
        }
    }
    sizes
}

/// Deterministic content digest of a solved layout (blake3 of the canonical JSON rect list) — the
/// layout analogue of the frame's `render_digest`. Two independent solves of the same tree at the
/// same box yield byte-identical digests.
pub fn layout_digest(rects: &[Rect]) -> String {
    // Canonical, dependency-light serialization: `id␟x,y,w,h\n` per rect. The unit separator keeps
    // the id and the integers unambiguous regardless of id contents.
    let mut s = String::new();
    for r in rects {
        s.push_str(&r.id);
        s.push('\u{1f}');
        s.push_str(&r.x.to_string());
        s.push(',');
        s.push_str(&r.y.to_string());
        s.push(',');
        s.push_str(&r.w.to_string());
        s.push(',');
        s.push_str(&r.h.to_string());
        s.push('\n');
    }
    format!("sha256:{}", blake3::hash(s.as_bytes()).to_hex())
}

/// Compose a TABLE: a header row + one data row per entry, all sharing `col_weights` so the columns
/// ALIGN across every row — the layout engine resolves identical column x-positions for the header
/// and every data row, so a table is "just" a `Col` of `Row`s with no per-cell coordinate math. Each
/// row is a `Row` of `Flex` cells; `header_ids[c]` / `rows[r].1[c]` name the cell at column `c`, and
/// `rows[r].0` names the data-row container (a hit-test / selection target behind its cells).
pub fn table(
    id: &str,
    header_ids: &[String],
    col_weights: &[i64],
    header_h: i64,
    row_h: i64,
    rows: &[(String, Vec<String>)],
) -> LayoutBox {
    let cells = |ids: &[String]| -> Vec<LayoutBox> {
        ids.iter()
            .zip(col_weights)
            .map(|(cid, w)| LayoutBox::leaf(cid.clone(), Size::Flex(*w)))
            .collect()
    };
    let mut children = vec![LayoutBox::row(format!("{id}:header"), Size::Fixed(header_h), cells(header_ids))];
    for (rid, cids) in rows {
        children.push(LayoutBox::row(rid.clone(), Size::Fixed(row_h), cells(cids)));
    }
    LayoutBox::col(id, Size::Flex(1), children)
}

// ── Text DSL: author a layout as text (LAB-FRAME-LAYOUT-VOCAB-P4) ────────────────────────────────

/// A parse error from the layout DSL, carrying a 1-based line number.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ParseError {
    pub line: usize,
    pub msg: String,
}

const MAX_PARSE_DEPTH: usize = 32;

/// Parse a compact, indentation-based layout DSL into a `LayoutBox` tree. Each line is
/// `<kind> <id> [fixed N | flex N] [pad N] [gap N] [cross N] [align start|center|end]`, where `kind`
/// is `col` / `row` / `leaf`;
/// two leading spaces nest a child under the line above. Blank lines and `#` / `--` comments are
/// ignored. **Total**: any malformed line yields a `ParseError` with its 1-based number — never a
/// panic — so it is safe to drive from a live text field.
pub fn parse(text: &str) -> Result<LayoutBox, ParseError> {
    let mut stack: Vec<(usize, LayoutBox)> = Vec::new();
    for (i, line) in text.lines().enumerate() {
        let lineno = i + 1;
        let trimmed = line.trim_start();
        if trimmed.is_empty() || trimmed.starts_with('#') || trimmed.starts_with("--") {
            continue;
        }
        let indent = line.len() - trimmed.len();
        if !line[..indent].chars().all(|c| c == ' ') {
            return Err(ParseError { line: lineno, msg: "indentation must be spaces (2 per level)".into() });
        }
        if indent % 2 != 0 {
            return Err(ParseError { line: lineno, msg: "indentation must be a multiple of 2 spaces".into() });
        }
        let depth = indent / 2;
        if depth > MAX_PARSE_DEPTH {
            return Err(ParseError { line: lineno, msg: "layout nested too deep".into() });
        }
        let node = parse_line(trimmed, lineno)?;

        if stack.is_empty() {
            if depth != 0 {
                return Err(ParseError { line: lineno, msg: "the first node must be at indentation 0".into() });
            }
        } else {
            while let Some((d, _)) = stack.last() {
                if *d >= depth {
                    let (_, child) = stack.pop().unwrap();
                    stack.last_mut().unwrap().1.children.push(child);
                } else {
                    break;
                }
            }
            match stack.last().map(|(d, _)| *d) {
                Some(pd) if pd + 1 == depth => {}
                _ => return Err(ParseError {
                    line: lineno,
                    msg: "bad indentation (a child must be exactly one level deeper than its parent)".into(),
                }),
            }
        }
        stack.push((depth, node));
    }
    if stack.is_empty() {
        return Err(ParseError { line: 0, msg: "empty layout".into() });
    }
    while stack.len() > 1 {
        let (_, child) = stack.pop().unwrap();
        stack.last_mut().unwrap().1.children.push(child);
    }
    Ok(stack.pop().unwrap().1)
}

fn parse_line(s: &str, lineno: usize) -> Result<LayoutBox, ParseError> {
    let err = |msg: String| ParseError { line: lineno, msg };
    let mut toks = s.split_whitespace();
    let kind = toks.next().ok_or_else(|| err("empty node".into()))?;
    let id = toks.next().ok_or_else(|| err(format!("`{kind}` needs an id")))?;
    let dir = match kind {
        "col" | "leaf" => Dir::Col,
        "row" => Dir::Row,
        other => return Err(err(format!("unknown node kind `{other}` (expected col/row/leaf)"))),
    };
    let mut b = LayoutBox {
        id: id.to_string(),
        dir,
        main: Size::Flex(1),
        cross: CrossSize::Stretch,
        align: Align::Start,
        pad: 0,
        gap: 0,
        children: Vec::new(),
    };
    while let Some(key) = toks.next() {
        let val = toks.next().ok_or_else(|| err(format!("`{key}` needs a value")))?;
        let int = || val.parse::<i64>().map_err(|_| err(format!("`{key}` value `{val}` is not an integer")));
        match key {
            "fixed" => b.main = Size::Fixed(int()?.max(0)),
            "flex" => b.main = Size::Flex(int()?.max(1)),
            "pad" => b.pad = int()?.max(0),
            "gap" => b.gap = int()?.max(0),
            "cross" => b.cross = CrossSize::Fixed(int()?.max(0)),
            "align" => {
                b.align = match val {
                    "start" => Align::Start,
                    "center" => Align::Center,
                    "end" => Align::End,
                    other => return Err(err(format!("unknown align `{other}` (expected start/center/end)"))),
                }
            }
            other => return Err(err(format!("unknown attribute `{other}` (expected fixed/flex/pad/gap/cross/align)"))),
        }
    }
    Ok(b)
}

fn esc(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;")
}

fn depths(b: &LayoutBox, d: usize, out: &mut Vec<(String, usize)>) {
    out.push((b.id.clone(), d));
    for c in &b.children {
        depths(c, d + 1, out);
    }
}

/// Render a SOLVED layout tree to an inspection SVG: each box as a labeled rect, colored by nesting
/// depth (containers tinted, IDs labeled). The visual behind a live "author layout as text"
/// playground. Box ids are HTML-escaped, so arbitrary author text is safe.
pub fn preview_svg(root: &LayoutBox, w: i64, h: i64) -> String {
    const PALETTE: [&str; 6] = ["#1f6feb", "#238636", "#9e6a03", "#8957e5", "#1f6f8b", "#bc4c00"];
    let rects = solve(root, 0, 0, w, h);
    let mut dv = Vec::new();
    depths(root, 0, &mut dv);
    let depth_of = |id: &str| dv.iter().find(|(k, _)| k == id).map(|(_, d)| *d).unwrap_or(0);

    let mut body = String::new();
    for r in &rects {
        let d = depth_of(&r.id);
        let c = PALETTE[d % PALETTE.len()];
        body.push_str(&format!(
            "  <rect x=\"{}\" y=\"{}\" width=\"{}\" height=\"{}\" rx=\"5\" fill=\"{c}\" fill-opacity=\"0.14\" stroke=\"{c}\" stroke-opacity=\"0.9\"/>\n",
            r.x, r.y, r.w.max(0), r.h.max(0)
        ));
        if r.w >= 30 && r.h >= 14 {
            body.push_str(&format!(
                "  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"11\" fill=\"{c}\">{}</text>\n",
                r.x + 5, r.y + 13, esc(&r.id)
            ));
        }
    }
    format!(
        "<svg viewBox=\"0 0 {w} {h}\" xmlns=\"http://www.w3.org/2000/svg\">\n  <rect width=\"{w}\" height=\"{h}\" fill=\"#010409\"/>\n{body}</svg>\n"
    )
}

/// Render a `ParseError` as an SVG card — the "your layout text is malformed" view for the live
/// playground. The message is HTML-escaped.
pub fn error_svg(e: &ParseError, w: i64, h: i64) -> String {
    let loc = if e.line > 0 { format!("line {}", e.line) } else { "layout".to_string() };
    format!(
        "<svg viewBox=\"0 0 {w} {h}\" xmlns=\"http://www.w3.org/2000/svg\">\n  <rect width=\"{w}\" height=\"{h}\" fill=\"#010409\"/>\n  <rect x=\"12\" y=\"12\" width=\"{cw}\" height=\"58\" rx=\"6\" fill=\"#3d1418\" stroke=\"#f85149\"/>\n  <text x=\"24\" y=\"38\" font-family=\"monospace\" font-size=\"13\" fill=\"#f85149\">parse error · {loc}</text>\n  <text x=\"24\" y=\"57\" font-family=\"monospace\" font-size=\"12\" fill=\"#ff9ca0\">{msg}</text>\n</svg>\n",
        cw = (w - 24).max(0),
        msg = esc(&e.msg),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rect<'a>(rs: &'a [Rect], id: &str) -> &'a Rect {
        rs.iter().find(|r| r.id == id).unwrap_or_else(|| panic!("no rect {id}"))
    }

    #[test]
    fn leaf_is_its_own_box() {
        let rs = solve(&LayoutBox::leaf("a", Size::Fixed(10)), 5, 7, 100, 40);
        assert_eq!(rs, vec![Rect { id: "a".into(), x: 5, y: 7, w: 100, h: 40 }]);
    }

    #[test]
    fn col_stacks_fixed_rows_with_pad_and_gap() {
        // a list: 3 fixed-height rows, pad 8, gap 4 → exact y positions
        let tree = LayoutBox::col(
            "list",
            Size::Fixed(0),
            vec![
                LayoutBox::leaf("r0", Size::Fixed(20)),
                LayoutBox::leaf("r1", Size::Fixed(20)),
                LayoutBox::leaf("r2", Size::Fixed(20)),
            ],
        )
        .pad(8)
        .gap(4);
        let rs = solve(&tree, 0, 0, 200, 400);
        // content starts at (8,8), each row full content width (200-16=184)
        assert_eq!(rect(&rs, "r0").y, 8);
        assert_eq!(rect(&rs, "r1").y, 8 + 20 + 4);
        assert_eq!(rect(&rs, "r2").y, 8 + 2 * (20 + 4));
        assert!(rs.iter().all(|r| r.id == "list" || r.w == 184));
    }

    #[test]
    fn row_flex_columns_fill_exactly_with_deterministic_remainder() {
        // 3 equal flex columns over content width 100 (no pad/gap) → 34,33,33 summing to 100
        let tree = LayoutBox::row(
            "bar",
            Size::Fixed(0),
            vec![
                LayoutBox::leaf("c0", Size::Flex(1)),
                LayoutBox::leaf("c1", Size::Flex(1)),
                LayoutBox::leaf("c2", Size::Flex(1)),
            ],
        );
        let rs = solve(&tree, 0, 0, 100, 50);
        let ws: Vec<i64> = ["c0", "c1", "c2"].iter().map(|id| rect(&rs, id).w).collect();
        assert_eq!(ws, vec![34, 33, 33], "leftover px to earliest flex children");
        assert_eq!(ws.iter().sum::<i64>(), 100, "flex fills the content box exactly");
        // children are placed left→right, contiguous
        assert_eq!(rect(&rs, "c0").x, 0);
        assert_eq!(rect(&rs, "c1").x, 34);
        assert_eq!(rect(&rs, "c2").x, 67);
    }

    #[test]
    fn fixed_and_flex_mix_in_a_row() {
        // sidebar fixed 180, main flex(1), inspector fixed 200 over width 700, gap 10
        let tree = LayoutBox::row(
            "screen",
            Size::Fixed(0),
            vec![
                LayoutBox::leaf("sidebar", Size::Fixed(180)),
                LayoutBox::leaf("main", Size::Flex(1)),
                LayoutBox::leaf("inspector", Size::Fixed(200)),
            ],
        )
        .gap(10);
        let rs = solve(&tree, 0, 0, 700, 440);
        // gaps total 20; flex main = 700 - 180 - 200 - 20 = 300
        assert_eq!(rect(&rs, "sidebar").w, 180);
        assert_eq!(rect(&rs, "main").w, 300);
        assert_eq!(rect(&rs, "inspector").w, 200);
        assert_eq!(rect(&rs, "sidebar").x, 0);
        assert_eq!(rect(&rs, "main").x, 180 + 10);
        assert_eq!(rect(&rs, "inspector").x, 180 + 10 + 300 + 10);
    }

    #[test]
    fn nesting_recurses() {
        // a workbench shape: Row[ sidebar(col of 2 leads) , main(flex col of 2 fields) ]
        let tree = LayoutBox::row(
            "wb",
            Size::Fixed(0),
            vec![
                LayoutBox::col(
                    "sidebar",
                    Size::Fixed(120),
                    vec![
                        LayoutBox::leaf("lead0", Size::Fixed(30)),
                        LayoutBox::leaf("lead1", Size::Fixed(30)),
                    ],
                )
                .pad(6)
                .gap(6),
                LayoutBox::col(
                    "main",
                    Size::Flex(1),
                    vec![
                        LayoutBox::leaf("f0", Size::Fixed(40)),
                        LayoutBox::leaf("f1", Size::Fixed(40)),
                    ],
                )
                .pad(10),
            ],
        );
        let rs = solve(&tree, 0, 0, 400, 200);
        // sidebar is fixed 120 at x=0; leads stacked inside its padded content (x=6,y=6)
        assert_eq!(rect(&rs, "sidebar").w, 120);
        assert_eq!(rect(&rs, "lead0").x, 6);
        assert_eq!(rect(&rs, "lead0").y, 6);
        assert_eq!(rect(&rs, "lead1").y, 6 + 30 + 6);
        // main takes the rest (400-120=280) at x=120; fields inside its pad-10 content
        assert_eq!(rect(&rs, "main").w, 280);
        assert_eq!(rect(&rs, "main").x, 120);
        assert_eq!(rect(&rs, "f0").x, 130);
        assert_eq!(rect(&rs, "f0").y, 10);
        assert_eq!(rect(&rs, "f1").y, 10 + 40);
        assert_eq!(rect(&rs, "f0").w, 280 - 20);
    }

    #[test]
    fn deterministic_and_digest_stable() {
        let tree = LayoutBox::row(
            "r",
            Size::Fixed(0),
            vec![
                LayoutBox::leaf("a", Size::Flex(2)),
                LayoutBox::leaf("b", Size::Flex(1)),
            ],
        )
        .pad(4)
        .gap(3);
        let a = solve(&tree, 1, 2, 333, 99);
        let b = solve(&tree, 1, 2, 333, 99);
        assert_eq!(a, b, "same tree + same box → identical rects");
        assert_eq!(layout_digest(&a), layout_digest(&b));
        // weight 2:1 over content 333-8-3=322 → 215,107 (322/3=107 r1 → earliest flex gets +1)
        let wa = a.iter().find(|r| r.id == "a").unwrap().w;
        let wb = a.iter().find(|r| r.id == "b").unwrap().w;
        assert_eq!(wa + wb, 322, "flex fills content width exactly");
        assert_eq!((wa, wb), (215, 107));
    }

    #[test]
    fn over_padding_clamps_to_zero_no_panic() {
        let tree = LayoutBox::col(
            "tiny",
            Size::Fixed(0),
            vec![LayoutBox::leaf("c", Size::Flex(1))],
        )
        .pad(50);
        // box smaller than 2*pad → content clamps to 0, child gets a 0-size rect, no overflow/panic
        let rs = solve(&tree, 0, 0, 40, 40);
        let c = rect(&rs, "c");
        assert_eq!((c.w, c.h), (0, 0));
    }

    #[test]
    fn table_columns_align_across_rows() {
        let cols = [3, 2, 1];
        let t = table(
            "t",
            &["h0".into(), "h1".into(), "h2".into()],
            &cols,
            30,
            24,
            &[
                ("r0".into(), vec!["r0c0".into(), "r0c1".into(), "r0c2".into()]),
                ("r1".into(), vec!["r1c0".into(), "r1c1".into(), "r1c2".into()]),
            ],
        );
        let rs = solve(&t, 0, 0, 600, 400);
        // every column's x AND width are identical for the header and every data row → aligned columns
        for c in 0..3 {
            let h = rect(&rs, &format!("h{c}"));
            for r in ["r0", "r1"] {
                let cell = rect(&rs, &format!("{r}c{c}"));
                assert_eq!(cell.x, h.x, "col {c} x aligns across header/{r}");
                assert_eq!(cell.w, h.w, "col {c} width aligns across header/{r}");
            }
        }
        // weights 3:2:1 over width 600 → 300/200/100 at x 0/300/500
        assert_eq!((rect(&rs, "h0").x, rect(&rs, "h0").w), (0, 300));
        assert_eq!((rect(&rs, "h1").x, rect(&rs, "h1").w), (300, 200));
        assert_eq!((rect(&rs, "h2").x, rect(&rs, "h2").w), (500, 100));
        // rows stack: header h=30 at y0, r0 at 30, r1 at 54
        assert_eq!(rect(&rs, "r0").y, 30);
        assert_eq!(rect(&rs, "r1").y, 54);
    }

    #[test]
    fn parse_builds_the_same_tree_as_the_builder() {
        let src = "col root pad 16 gap 12\n  leaf title fixed 28\n  row body flex 1 gap 10\n    leaf sidebar fixed 220\n    col main flex 1\n";
        let t = parse(src).unwrap();
        assert_eq!(t.id, "root");
        assert_eq!((t.pad, t.gap), (16, 12));
        assert_eq!(t.children.len(), 2);
        assert_eq!(t.children[0].id, "title");
        assert!(matches!(t.children[0].main, Size::Fixed(28)));
        let body = &t.children[1];
        assert_eq!(body.id, "body");
        assert!(matches!(body.dir, Dir::Row));
        assert_eq!(body.children.iter().map(|c| c.id.as_str()).collect::<Vec<_>>(), vec!["sidebar", "main"]);
        // and the parsed tree solves like any other
        let rs = solve(&t, 0, 0, 600, 400);
        assert_eq!(rect(&rs, "root").w, 600);
    }

    #[test]
    fn parse_ignores_comments_and_blank_lines() {
        let t = parse("# header comment\ncol root gap 4\n\n  -- child comment\n  leaf a fixed 10\n").unwrap();
        assert_eq!(t.children.len(), 1);
        assert_eq!(t.children[0].id, "a");
    }

    #[test]
    fn parse_reports_errors_with_line_numbers_and_never_panics() {
        assert_eq!(parse("box x").unwrap_err().line, 1); // unknown kind
        assert_eq!(parse("col").unwrap_err().line, 1); // missing id
        assert_eq!(parse("col root\n leaf a fixed 1").unwrap_err().line, 2); // odd indent
        assert_eq!(parse("col root\n    leaf a fixed 1").unwrap_err().line, 2); // indent jump
        assert_eq!(parse("  col root").unwrap_err().line, 1); // first node indented
        let e = parse("col root\n  leaf a fixed wide").unwrap_err();
        assert!(e.line == 2 && e.msg.contains("not an integer"));
        assert!(parse("leaf a wiggle 3").unwrap_err().msg.contains("unknown attribute"));
        assert!(parse("\n# only a comment\n").is_err()); // empty
    }

    #[test]
    fn preview_svg_is_deterministic_and_escapes_author_text() {
        let t = parse("col root pad 8\n  leaf a fixed 30\n  leaf b flex 1").unwrap();
        assert_eq!(preview_svg(&t, 200, 120), preview_svg(&t, 200, 120));
        assert!(preview_svg(&t, 200, 120).starts_with("<svg"));
        // arbitrary author ids are escaped — no raw markup injection from the live text field
        let evil = parse("leaf <script>x</script> fixed 50").unwrap();
        let svg = preview_svg(&evil, 200, 80);
        assert!(!svg.contains("<script>") && svg.contains("&lt;script&gt;"));
        // a parse error renders a card, not a panic
        assert!(error_svg(&parse("nope").unwrap_err(), 200, 80).contains("parse error"));
    }

    #[test]
    fn cross_align_positions_fixed_cross_children() {
        // ROW: cross axis = vertical. A 40-tall child in a 100-tall row, centered → y = (100-40)/2.
        let center = LayoutBox::row("r", Size::Fixed(0), vec![LayoutBox::leaf("a", Size::Flex(1)).cross(40)])
            .align(Align::Center);
        let a = rect(&solve(&center, 0, 0, 300, 100), "a").clone();
        assert_eq!((a.y, a.h), (30, 40));
        assert_eq!((a.x, a.w), (0, 300)); // main axis still flexes to fill

        let end = LayoutBox::row("r", Size::Fixed(0), vec![LayoutBox::leaf("a", Size::Flex(1)).cross(40)])
            .align(Align::End);
        assert_eq!(rect(&solve(&end, 0, 0, 300, 100), "a").y, 60);

        // COL: cross axis = horizontal. A 120-wide child in a 400-wide col, centered → x = (400-120)/2.
        let col = LayoutBox::col("c", Size::Fixed(0), vec![LayoutBox::leaf("b", Size::Flex(1)).cross(120)])
            .align(Align::Center);
        let b = rect(&solve(&col, 0, 0, 400, 200), "b").clone();
        assert_eq!((b.x, b.w), (140, 120));

        // a stretched sibling still fills (ignores align), so the two models compose
        let mixed = LayoutBox::col("c", Size::Fixed(0), vec![
            LayoutBox::leaf("full", Size::Fixed(20)),
            LayoutBox::leaf("chip", Size::Fixed(20)).cross(80),
        ]).align(Align::Center);
        let rs = solve(&mixed, 0, 0, 200, 100);
        assert_eq!((rect(&rs, "full").x, rect(&rs, "full").w), (0, 200));
        assert_eq!((rect(&rs, "chip").x, rect(&rs, "chip").w), (60, 80));
    }

    #[test]
    fn dsl_parses_cross_and_align() {
        let t = parse("row bar align center\n  leaf chip fixed 100 cross 24").unwrap();
        assert!(matches!(t.align, Align::Center));
        assert!(matches!(t.children[0].cross, CrossSize::Fixed(24)));
        // a 24-tall chip centered in a 60-tall bar → y = 18
        assert_eq!(rect(&solve(&t, 0, 0, 300, 60), "chip").y, 18);
        // bad align word is a clean error
        assert!(parse("row bar align middle").unwrap_err().msg.contains("unknown align"));
    }

    #[test]
    fn all_fixed_children_keep_their_sizes() {
        let tree = LayoutBox::col(
            "c",
            Size::Fixed(0),
            vec![
                LayoutBox::leaf("a", Size::Fixed(10)),
                LayoutBox::leaf("b", Size::Fixed(20)),
            ],
        );
        let rs = solve(&tree, 0, 0, 100, 1000);
        assert_eq!(rect(&rs, "a").h, 10);
        assert_eq!(rect(&rs, "b").h, 20);
        assert_eq!(rect(&rs, "b").y, 10); // stacked, start-aligned, leftover space unused
    }
}
