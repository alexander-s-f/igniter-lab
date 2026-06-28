//! LAB-FRAME-3D-GAME-P1 — the gamedig payoff: a DETERMINISTIC game loop with replay + time-travel,
//! for free from the same integer/machine-free engine.
//!
//! The world is `N` bouncing bodies under integer physics in a 3D box. State at any tick is a PURE
//! FUNCTION of `(initial_world, input_log, tick)`: `world_at(t)` re-simulates from the start applying
//! the recorded inputs. So determinism gives, for nothing extra:
//!   • REPLAY     — the same input log reproduces the exact same trajectories (bit-identical);
//!   • TIME-TRAVEL— scrub to any past/future tick by re-running the pure function (no snapshots);
//!   • LOCKSTEP   — two instances fed the same inputs stay bit-identical.
//! Pure integer math (no `f64`, no clock, no RNG, no kernel). Rendered as 3D wireframe via `scene3d`.

use crate::scene3d::{CUBE, EDGES, FP, V3};

const CANVAS_W: i64 = 640;
const CANVAS_H: i64 = 480;
const N: usize = 6;
const BOUND: i64 = 3 * FP; // box half-extent
const GRAV: i64 = FP / 220; // downward pull per tick
const DAMP: i64 = 244; // /256 ≈ 0.95 velocity retained on a bounce
const BODY: i64 = FP * 55 / 100; // body cube half-size

#[derive(Clone, Copy)]
struct Body {
    p: V3,
    v: V3,
}

fn sign(n: i64) -> i64 {
    (n > 0) as i64 - (n < 0) as i64
}

/// The initial world — deterministic positions + velocities (no RNG).
fn initial() -> [Body; N] {
    let mut w = [Body { p: V3 { x: 0, y: 0, z: 0 }, v: V3 { x: 0, y: 0, z: 0 } }; N];
    for (i, b) in w.iter_mut().enumerate() {
        let i = i as i64;
        b.p = V3 { x: (i - 3) * FP * 7 / 10, y: FP + (i % 3) * FP / 2, z: (i % 2) * FP - FP / 2 };
        b.v = V3 { x: ((i * 7) % 5 - 2) * FP / 48, y: 0, z: ((i * 3) % 5 - 2) * FP / 48 };
    }
    w
}

fn reflect(pos: &mut i64, vel: &mut i64) {
    if *pos > BOUND {
        *pos = 2 * BOUND - *pos;
        *vel = -*vel * DAMP / 256;
    } else if *pos < -BOUND {
        *pos = -2 * BOUND - *pos;
        *vel = -*vel * DAMP / 256;
    }
}

/// One fixed timestep: optional `boom` impulse (radial-out + up), gravity, integrate, bounce.
fn step(world: &[Body; N], boom: bool) -> [Body; N] {
    let mut next = *world;
    for b in next.iter_mut() {
        if boom {
            b.v.x += sign(b.p.x) * FP / 14;
            b.v.z += sign(b.p.z) * FP / 14;
            b.v.y += FP / 7;
        }
        b.v.y -= GRAV;
        b.p.x += b.v.x;
        b.p.y += b.v.y;
        b.p.z += b.v.z;
        reflect(&mut b.p.x, &mut b.v.x);
        reflect(&mut b.p.y, &mut b.v.y);
        reflect(&mut b.p.z, &mut b.v.z);
    }
    next
}

// ── Projection / render (3D wireframe via the shared scene3d primitives) ─────────────────────────

fn project(p: V3) -> (i64, i64, i64) {
    let (cx, cy, focal, dist) = (CANVAS_W / 2, CANVAS_H / 2, 600, FP * 11);
    let d = (p.z + dist).max(1);
    (cx + p.x * focal / d, cy - p.y * focal / d, d)
}

/// Push a cube's 12 edges (centre `c`, half-size `s`) as `(x1,y1,x2,y2,shade)` into `out`.
fn push_cube(out: &mut Vec<(i64, i64, i64, i64, i64)>, c: V3, s: i64, base_shade: i64) {
    let pts: [(i64, i64, i64); 8] = std::array::from_fn(|k| {
        let v = CUBE[k];
        project(V3 { x: c.x + v.x * s / FP, y: c.y + v.y * s / FP, z: c.z + v.z * s / FP })
    });
    for &(a, b) in EDGES.iter() {
        let (x1, y1, da) = pts[a];
        let (x2, y2, db) = pts[b];
        let depth = (da + db) / 2;
        let near = FP * 11 - BOUND;
        let far = FP * 11 + BOUND;
        let t = ((depth - near) * 170 / (far - near).max(1)).clamp(0, 170);
        out.push((x1, y1, x2, y2, (base_shade - t).clamp(40, 255)));
    }
}

fn render(world: &[Body; N]) -> String {
    let mut edges: Vec<(i64, i64, i64, i64, i64)> = Vec::new();
    // the bounding box (faint reference)
    push_cube(&mut edges, V3 { x: 0, y: 0, z: 0 }, BOUND, 110);
    // the bodies (brighter)
    for b in world.iter() {
        push_cube(&mut edges, b.p, BODY, 255);
    }
    edges.sort_by(|a, b| a.4.cmp(&b.4)); // far→near
    let mut body = String::new();
    for (x1, y1, x2, y2, shade) in edges {
        let c = shade.clamp(0, 255);
        body.push_str(&format!(
            "  <line x1=\"{x1}\" y1=\"{y1}\" x2=\"{x2}\" y2=\"{y2}\" stroke=\"rgb({},{},{})\" stroke-width=\"1.4\"/>\n",
            c * 7 / 10, c / 3, c
        ));
    }
    format!(
        "<svg viewBox=\"0 0 {CANVAS_W} {CANVAS_H}\" xmlns=\"http://www.w3.org/2000/svg\">\n  <rect width=\"{CANVAS_W}\" height=\"{CANVAS_H}\" fill=\"#070510\"/>\n{body}</svg>\n"
    )
}

// ── The game: pure (initial, input log, tick) → world ────────────────────────────────────────────

/// A deterministic game. The only mutable bits are the INPUT LOG (ticks a `boom` was fired) and the
/// current `tick`; the world is always recomputed from them, so replay and time-travel are free.
pub struct Game {
    booms: Vec<u64>,
    tick: u64,
    max_tick: u64,
}

impl Default for Game {
    fn default() -> Self {
        Self::new()
    }
}

impl Game {
    pub fn new() -> Self {
        Self { booms: Vec::new(), tick: 0, max_tick: 0 }
    }

    /// The world at tick `t` — re-simulate from the initial world applying logged booms. PURE.
    fn world_at(&self, t: u64) -> [Body; N] {
        let mut w = initial();
        for k in 0..t {
            w = step(&w, self.booms.binary_search(&k).is_ok());
        }
        w
    }

    /// Advance one fixed timestep (the play driver).
    pub fn advance(&mut self) {
        self.tick += 1;
        self.max_tick = self.max_tick.max(self.tick);
    }

    /// Jump to any tick — TIME TRAVEL (re-simulates the pure function).
    pub fn seek(&mut self, t: u64) {
        self.tick = t.min(self.max_tick);
    }

    /// Record a `boom` input at the current tick (affects the step into the next frame).
    pub fn boom(&mut self) {
        let t = self.tick;
        if self.booms.binary_search(&t).is_err() {
            self.booms.push(t);
            self.booms.sort_unstable();
        }
    }

    pub fn tick(&self) -> u64 {
        self.tick
    }
    pub fn max_tick(&self) -> u64 {
        self.max_tick
    }
    pub fn boom_count(&self) -> u32 {
        self.booms.len() as u32
    }
    pub fn render_svg(&self) -> String {
        render(&self.world_at(self.tick))
    }
    pub fn digest(&self) -> String {
        let w = self.world_at(self.tick);
        let mut s = String::new();
        for b in w.iter() {
            s.push_str(&format!("{},{},{};", b.p.x, b.p.y, b.p.z));
        }
        format!("sha256:{}", blake3::hash(s.as_bytes()).to_hex())
    }
    /// Clear the input log and rewind (a fresh game).
    pub fn reset(&mut self) {
        self.booms.clear();
        self.tick = 0;
        self.max_tick = 0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pos_digest(g: &Game, t: u64) -> String {
        let mut g2 = Game { booms: g.booms.clone(), tick: t, max_tick: t };
        g2.seek(t);
        g2.digest()
    }

    #[test]
    fn world_is_a_pure_function_of_inputs_and_tick() {
        let g = Game::new();
        // same tick, recomputed, is identical
        assert_eq!(pos_digest(&g, 50), pos_digest(&g, 50));
        // motion actually happens
        assert_ne!(pos_digest(&g, 0), pos_digest(&g, 50));
    }

    #[test]
    fn replay_is_bit_identical() {
        // a game with two booms in the log, advanced 80 ticks twice
        let run = || {
            let mut g = Game::new();
            for _ in 0..80 {
                g.advance();
                if g.tick() == 10 || g.tick() == 40 {
                    g.boom();
                }
            }
            g.digest()
        };
        assert_eq!(run(), run());
    }

    #[test]
    fn time_travel_seek_matches_direct_simulation() {
        let mut g = Game::new();
        for _ in 0..100 {
            g.advance();
            if g.tick() == 15 {
                g.boom();
            }
        }
        let at100 = g.digest();
        // scrub back to 30, then forward to 100 — pure function, so identical
        g.seek(30);
        let at30 = g.digest();
        g.seek(100);
        assert_eq!(g.digest(), at100, "time-travel forward reproduces the future exactly");
        // and seeking to 30 again gives the same past
        g.seek(30);
        assert_eq!(g.digest(), at30, "the past is reproducible");
    }

    #[test]
    fn an_input_changes_the_future() {
        let mut quiet = Game::new();
        for _ in 0..60 {
            quiet.advance();
        }
        let mut kicked = Game::new();
        for _ in 0..60 {
            kicked.advance();
            if kicked.tick() == 5 {
                kicked.boom();
            }
        }
        assert_ne!(quiet.digest(), kicked.digest(), "a boom diverges the timeline");
    }

    #[test]
    fn bodies_stay_bounded() {
        let mut g = Game::new();
        for _ in 0..200 {
            g.advance();
            if g.tick() % 25 == 0 {
                g.boom();
            }
        }
        let w = g.world_at(g.tick());
        for b in w.iter() {
            for c in [b.p.x, b.p.y, b.p.z] {
                assert!(c.abs() <= BOUND + FP, "body escaped the box: {c}");
            }
        }
    }

    #[test]
    fn render_is_wireframe_svg() {
        let g = Game::new();
        let svg = g.render_svg();
        assert!(svg.starts_with("<svg"));
        // box (12) + N bodies (12 each)
        assert_eq!(svg.matches("<line").count(), 12 * (N + 1));
    }
}
