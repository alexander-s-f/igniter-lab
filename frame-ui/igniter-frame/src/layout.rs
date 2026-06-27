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

/// A node in the layout tree. Cross-axis sizing is "stretch": a child fills its parent's content
/// extent on the cross axis (the v0 default — predictable and deterministic; per-child cross
/// alignment is a later slice).
#[derive(Clone, Debug)]
pub struct LayoutBox {
    pub id: String,
    /// How THIS box arranges its own children (ignored for a leaf).
    pub dir: Dir,
    /// This box's size along its parent's main axis.
    pub main: Size,
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
        let (rx, ry, rw, rh) = if b.dir == Dir::Col {
            (cx, offset, cross, main)
        } else {
            (offset, cy, main, cross)
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
