//! LAB-FRAME-3D-P1 — Ceiling B/C: a deterministic, machine-free 3D scene.
//!
//! The frame-ui audit named Ceiling B (the frame data model is screen-points-only — no depth /
//! topology / material, so no 3D) and Ceiling C (the game loop has the right `(world, intent) ->
//! deltas` shape but no `dt` / fixed-timestep driver). This module lifts both with the SAME engine
//! philosophy as the 2D layout vocab: **pure integer math, no `f64`, no clock/RNG, no kernel** — so it
//! is deterministic by construction (bit-identical across architectures, since only integer ops and a
//! precomputed table are used) and replayable (same tick ⇒ same digest).
//!
//! It carries the 3D data the 2D box model lacks — vertices with depth (`z`), topology (edges), and
//! depth-shaded material — and projects them through a fixed-point perspective camera to integer
//! screen coordinates, rendered as a painter-sorted wireframe SVG. A fixed-timestep `tick` advances
//! rotation, so the scene animates deterministically.

pub const FP: i64 = 4096; // fixed-point unit (1.0)

/// sin(i/256 * 2π) * 4096, precomputed (machine-free, no runtime f64). cos(a)=SIN256[(a+64)&255].
pub const SIN256: [i64; 256] = [
    0, 101, 201, 301, 401, 501, 601, 700, 799, 897, 995, 1092, 1189, 1285, 1380, 1474,
    1567, 1660, 1751, 1842, 1931, 2019, 2106, 2191, 2276, 2359, 2440, 2520, 2598, 2675, 2751, 2824,
    2896, 2967, 3035, 3102, 3166, 3229, 3290, 3349, 3406, 3461, 3513, 3564, 3612, 3659, 3703, 3745,
    3784, 3822, 3857, 3889, 3920, 3948, 3973, 3996, 4017, 4036, 4052, 4065, 4076, 4085, 4091, 4095,
    4096, 4095, 4091, 4085, 4076, 4065, 4052, 4036, 4017, 3996, 3973, 3948, 3920, 3889, 3857, 3822,
    3784, 3745, 3703, 3659, 3612, 3564, 3513, 3461, 3406, 3349, 3290, 3229, 3166, 3102, 3035, 2967,
    2896, 2824, 2751, 2675, 2598, 2520, 2440, 2359, 2276, 2191, 2106, 2019, 1931, 1842, 1751, 1660,
    1567, 1474, 1380, 1285, 1189, 1092, 995, 897, 799, 700, 601, 501, 401, 301, 201, 101,
    0, -101, -201, -301, -401, -501, -601, -700, -799, -897, -995, -1092, -1189, -1285, -1380, -1474,
    -1567, -1660, -1751, -1842, -1931, -2019, -2106, -2191, -2276, -2359, -2440, -2520, -2598, -2675, -2751, -2824,
    -2896, -2967, -3035, -3102, -3166, -3229, -3290, -3349, -3406, -3461, -3513, -3564, -3612, -3659, -3703, -3745,
    -3784, -3822, -3857, -3889, -3920, -3948, -3973, -3996, -4017, -4036, -4052, -4065, -4076, -4085, -4091, -4095,
    -4096, -4095, -4091, -4085, -4076, -4065, -4052, -4036, -4017, -3996, -3973, -3948, -3920, -3889, -3857, -3822,
    -3784, -3745, -3703, -3659, -3612, -3564, -3513, -3461, -3406, -3349, -3290, -3229, -3166, -3102, -3035, -2967,
    -2896, -2824, -2751, -2675, -2598, -2520, -2440, -2359, -2276, -2191, -2106, -2019, -1931, -1842, -1751, -1660,
    -1567, -1474, -1380, -1285, -1189, -1092, -995, -897, -799, -700, -601, -501, -401, -301, -201, -101,
];

fn sin(a: i64) -> i64 {
    SIN256[(a.rem_euclid(256)) as usize]
}
fn cos(a: i64) -> i64 {
    sin(a + 64)
}

/// A point in fixed-point world space (units of `FP` = 1.0).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct V3 {
    pub x: i64,
    pub y: i64,
    pub z: i64,
}

impl V3 {
    fn rot_y(self, a: i64) -> V3 {
        let (s, c) = (sin(a), cos(a));
        V3 { x: (self.x * c - self.z * s) / FP, y: self.y, z: (self.x * s + self.z * c) / FP }
    }
    fn rot_x(self, a: i64) -> V3 {
        let (s, c) = (sin(a), cos(a));
        V3 { x: self.x, y: (self.y * c - self.z * s) / FP, z: (self.y * s + self.z * c) / FP }
    }
    fn add(self, o: V3) -> V3 {
        V3 { x: self.x + o.x, y: self.y + o.y, z: self.z + o.z }
    }
    fn scale(self, n: i64) -> V3 {
        V3 { x: self.x * n / FP, y: self.y * n / FP, z: self.z * n / FP }
    }
}

/// Camera: a simple perspective projection to integer screen coords + the projected depth.
struct Camera {
    cx: i64,
    cy: i64,
    focal: i64,
    dist: i64,
}
impl Camera {
    /// (screen_x, screen_y, depth). Depth `z + dist` is clamped ≥ 1 so the divide is always defined.
    fn project(&self, p: V3) -> (i64, i64, i64) {
        let d = (p.z + self.dist).max(1);
        (self.cx + p.x * self.focal / d, self.cy - p.y * self.focal / d, d)
    }
}

// Unit cube: 8 vertices at ±FP, 12 edges.
/// Unit-cube vertices (±FP) — shared with the game-loop demo.
pub const CUBE: [V3; 8] = [
    V3 { x: -FP, y: -FP, z: -FP }, V3 { x: FP, y: -FP, z: -FP },
    V3 { x: FP, y: FP, z: -FP },   V3 { x: -FP, y: FP, z: -FP },
    V3 { x: -FP, y: -FP, z: FP },  V3 { x: FP, y: -FP, z: FP },
    V3 { x: FP, y: FP, z: FP },    V3 { x: -FP, y: FP, z: FP },
];
/// Cube edge topology (index pairs into [`CUBE`]).
pub const EDGES: [(usize, usize); 12] = [
    (0, 1), (1, 2), (2, 3), (3, 0), // back face
    (4, 5), (5, 6), (6, 7), (7, 4), // front face
    (0, 4), (1, 5), (2, 6), (3, 7), // connectors
];

const CANVAS_W: i64 = 640;
const CANVAS_H: i64 = 480;
const N_CUBES: i64 = 5;

/// One cube's world placement + spin for a given tick. Cube 0 is centred; 1..N orbit a ring.
fn cube_at(i: i64, tick: i64) -> (V3, i64, i64, i64) {
    if i == 0 {
        // central cube: bigger, spins on Y and X
        (V3 { x: 0, y: 0, z: 0 }, FP, tick * 3, tick * 2)
    } else {
        // orbiters: a ring of radius 2.6, orbit angle advances with tick, each spins
        let orbit = tick * 2 + (i - 1) * 64; // 64 = 90° apart
        let pos = V3 { x: (FP * 26) / 10, y: 0, z: 0 }.rot_y(orbit);
        (pos, (FP * 5) / 10, tick * 5 + i * 32, tick * 4)
    }
}

/// Project the whole scene at `tick` into screen-space edges, each with an average depth + shade.
/// Returns `(x1, y1, x2, y2, shade)` per edge, painter-sorted far→near (drawn in order).
fn project_edges(tick: i64) -> Vec<(i64, i64, i64, i64, i64)> {
    let cam = Camera { cx: CANVAS_W / 2, cy: CANVAS_H / 2, focal: 760, dist: FP * 7 };
    let mut out: Vec<(i64, i64, i64, i64, i64)> = Vec::new();
    for i in 0..N_CUBES {
        let (pos, size, ay, ax) = cube_at(i, tick);
        // project the 8 vertices of this cube
        let pts: Vec<(i64, i64, i64)> = CUBE
            .iter()
            .map(|v| cam.project(v.scale(size).rot_y(ay).rot_x(ax).add(pos)))
            .collect();
        for &(a, b) in EDGES.iter() {
            let (x1, y1, da) = pts[a];
            let (x2, y2, db) = pts[b];
            let depth = (da + db) / 2;
            // shade: nearer (smaller depth) = brighter. Map depth∈[dist-range, dist+range] → 60..255.
            let near = FP * 7 - FP * 4;
            let far = FP * 7 + FP * 4;
            let t = ((depth - near) * 195 / (far - near).max(1)).clamp(0, 195);
            out.push((x1, y1, x2, y2, 255 - t));
        }
    }
    // painter's algorithm: sort by depth descending (far first). Depth recomputed via the screen
    // span is unavailable, so re-sort by the stored shade (lower shade = farther) — stable + total.
    out.sort_by(|a, b| a.4.cmp(&b.4)); // ascending shade = far→near
    out
}

/// Render the scene at `tick` to a wireframe SVG (depth-shaded edges over a dark field).
pub fn render_scene(tick: i64) -> String {
    let mut body = String::new();
    for (x1, y1, x2, y2, shade) in project_edges(tick) {
        let c = shade.clamp(0, 255);
        // a cyan→teal wireframe shaded by depth
        body.push_str(&format!(
            "  <line x1=\"{x1}\" y1=\"{y1}\" x2=\"{x2}\" y2=\"{y2}\" stroke=\"rgb({},{},{})\" stroke-width=\"1.5\"/>\n",
            c / 4, c, (c * 9 / 10).min(255)
        ));
    }
    format!(
        "<svg viewBox=\"0 0 {CANVAS_W} {CANVAS_H}\" xmlns=\"http://www.w3.org/2000/svg\">\n  <rect width=\"{CANVAS_W}\" height=\"{CANVAS_H}\" fill=\"#05080d\"/>\n{body}</svg>\n"
    )
}

/// Content digest of the scene at `tick` (the integer edge geometry) — for replay/determinism proofs.
pub fn scene_digest(tick: i64) -> String {
    let mut s = String::new();
    for (x1, y1, x2, y2, shade) in project_edges(tick) {
        s.push_str(&format!("{x1},{y1},{x2},{y2},{shade}\n"));
    }
    format!("sha256:{}", blake3::hash(s.as_bytes()).to_hex())
}

/// A deterministic, fixed-timestep 3D runtime: `tick()` advances one frame; `render_svg()` projects
/// the scene at the current tick. No clock — the host drives the timestep (e.g. one tick per rAF).
pub struct SceneRuntime {
    tick: i64,
}

impl Default for SceneRuntime {
    fn default() -> Self {
        Self::new()
    }
}

impl SceneRuntime {
    pub fn new() -> Self {
        Self { tick: 0 }
    }
    /// Advance one fixed timestep.
    pub fn tick(&mut self) {
        self.tick = self.tick.wrapping_add(1);
    }
    pub fn frame_index(&self) -> u64 {
        self.tick as u64
    }
    pub fn render_svg(&self) -> String {
        render_scene(self.tick)
    }
    pub fn render_digest(&self) -> String {
        scene_digest(self.tick)
    }
    pub fn reset(&mut self) {
        self.tick = 0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn trig_table_is_exact_at_the_quadrants() {
        assert_eq!(sin(0), 0);
        assert_eq!(sin(64), FP); // 90°
        assert_eq!(sin(128), 0); // 180°
        assert_eq!(sin(192), -FP); // 270°
        assert_eq!(cos(0), FP);
        // pythagorean-ish: sin² + cos² ≈ FP² (within integer-rounding slack)
        for a in [7, 33, 100, 200] {
            let r = sin(a) * sin(a) + cos(a) * cos(a);
            assert!((r - FP * FP).abs() < FP * 4, "sin²+cos² off at {a}: {r}");
        }
    }

    #[test]
    fn rotation_is_integer_and_total() {
        let p = V3 { x: FP, y: 0, z: 0 };
        // a quarter turn about Y sends +x to -z (screen-into-page), within rounding
        let q = p.rot_y(64);
        assert_eq!(q.x, 0);
        assert!((q.z - FP).abs() <= 1);
    }

    #[test]
    fn scene_projects_to_in_bounds_integer_edges() {
        let edges = project_edges(0);
        // 5 cubes × 12 edges
        assert_eq!(edges.len(), (N_CUBES * 12) as usize);
        // all endpoints are finite integers near the canvas (perspective keeps them bounded)
        for (x1, y1, x2, y2, shade) in edges {
            for v in [x1, y1, x2, y2] {
                assert!(v > -2000 && v < 2000, "edge coord out of sane range: {v}");
            }
            assert!((0..=255).contains(&shade));
        }
    }

    #[test]
    fn deterministic_same_tick_same_bytes() {
        assert_eq!(render_scene(42), render_scene(42));
        assert_eq!(scene_digest(42), scene_digest(42));
        // animation actually changes the scene
        assert_ne!(scene_digest(0), scene_digest(10));
    }

    #[test]
    fn fixed_timestep_replay_is_bit_identical() {
        let run = || {
            let mut rt = SceneRuntime::new();
            for _ in 0..30 {
                rt.tick();
            }
            (rt.frame_index(), rt.render_digest())
        };
        assert_eq!(run(), run());
        // and a digest captured by replaying ticks equals rendering at that tick directly
        let mut rt = SceneRuntime::new();
        for _ in 0..30 {
            rt.tick();
        }
        assert_eq!(rt.render_digest(), scene_digest(30));
    }
}
