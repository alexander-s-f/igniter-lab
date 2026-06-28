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

/// One body, one fixed timestep: optional `boom` impulse (radial-out + up), gravity, integrate, bounce.
/// This is the SAME integer math as the `.ig` `StepBody` contract (`specimens/vm_game_app.ig`).
fn step_body(mut b: Body, boom: bool) -> Body {
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
    b
}

/// One fixed timestep over the whole world.
fn step(world: &[Body; N], boom: bool) -> [Body; N] {
    std::array::from_fn(|i| step_body(world[i], boom))
}

// ── `.ig`-world bridge: the exact same physics, over the flat `{px,py,pz,vx,vy,vz}` shape that the
//    `.ig` `Step` contract consumes — for cross-checking that the Rust and `.ig` reducers agree, and
//    for rendering a world produced by the VM. ────────────────────────────────────────────────────

/// A body's integer `id` carries through the JSON (it identifies a body for the `.ig` reducer); the
/// idless `Body` struct stays `Copy`, so the id is threaded at the JSON layer.
fn body_to_json(b: &Body, id: i64) -> serde_json::Value {
    serde_json::json!({ "px": b.p.x, "py": b.p.y, "pz": b.p.z, "vx": b.v.x, "vy": b.v.y, "vz": b.v.z, "id": id })
}

fn body_from_json(v: &serde_json::Value) -> Body {
    let g = |k: &str| v.get(k).and_then(|x| x.as_i64()).unwrap_or(0);
    Body { p: V3 { x: g("px"), y: g("py"), z: g("pz") }, v: V3 { x: g("vx"), y: g("vy"), z: g("vz") } }
}

fn body_id(v: &serde_json::Value) -> i64 {
    v.get("id").and_then(|k| k.as_i64()).unwrap_or(0)
}

/// The initial world as the `.ig` `World` JSON (`{bodies:[{px,…,id}]}`) — the single source of truth
/// fed to both the Rust loop and the `.ig` `Step`/`View`/`Reduce` contracts. Each body gets `id = i`.
pub fn initial_world_json() -> String {
    let bodies: Vec<serde_json::Value> =
        initial().iter().enumerate().map(|(i, b)| body_to_json(b, i as i64)).collect();
    serde_json::json!({ "bodies": bodies }).to_string()
}

/// One Rust timestep over an `.ig` `World` JSON — the cross-check mirror of the `.ig` `Step` contract
/// (preserves each body's `id`). Total/fail-closed: malformed input yields `{bodies:[]}`.
pub fn step_world_json(world_json: &str, boom: bool) -> String {
    let parsed: serde_json::Value = serde_json::from_str(world_json).unwrap_or(serde_json::Value::Null);
    let bodies: Vec<serde_json::Value> = parsed
        .get("bodies")
        .and_then(|b| b.as_array())
        .map(|arr| arr.iter().map(|b| body_to_json(&step_body(body_from_json(b), boom), body_id(b))).collect())
        .unwrap_or_default();
    serde_json::json!({ "bodies": bodies }).to_string()
}

/// One Rust KICK over an `.ig` `World` JSON — the mirror of the `.ig` `Reduce(world, target)` contract:
/// the body whose `id` matches gets a strong up + radial-out impulse. Total/fail-closed.
pub fn kick_world_json(world_json: &str, target: i64) -> String {
    let parsed: serde_json::Value = serde_json::from_str(world_json).unwrap_or(serde_json::Value::Null);
    let bodies: Vec<serde_json::Value> = parsed
        .get("bodies")
        .and_then(|b| b.as_array())
        .map(|arr| {
            arr.iter()
                .map(|bj| {
                    let mut b = body_from_json(bj);
                    if body_id(bj) == target {
                        b.v.x += sign(b.p.x) * 700;
                        b.v.z += sign(b.p.z) * 700;
                        b.v.y += 1400;
                    }
                    body_to_json(&b, body_id(bj))
                })
                .collect()
        })
        .unwrap_or_default();
    serde_json::json!({ "bodies": bodies }).to_string()
}

/// Host hit-test over a projected `.ig` `Scene` (`{markers:[{x,y,w,h,id}]}`): the `id` of the topmost
/// (largest = nearest) marker whose rect contains `(x, y)`, or `None` on a miss.
pub fn scene_hit(scene_json: &str, x: i64, y: i64) -> Option<i64> {
    let parsed: serde_json::Value = serde_json::from_str(scene_json).ok()?;
    let markers = parsed.get("markers")?.as_array()?;
    markers
        .iter()
        .filter_map(|m| {
            let g = |k: &str| m.get(k).and_then(|v| v.as_i64()).unwrap_or(0);
            let (mx, my, mw, mh) = (g("x"), g("y"), g("w"), g("h"));
            if x >= mx && x <= mx + mw && y >= my && y <= my + mh {
                Some((mw, g("id")))
            } else {
                None
            }
        })
        .max_by_key(|(w, _)| *w) // nearest (largest) marker wins on overlap
        .map(|(_, id)| id)
}

/// Project one body's centre to a depth-sized screen marker `(x, y, w, h)` — the Rust MIRROR of the
/// `.ig` `ProjectBody` contract (same camera: cx=320, cy=240, focal=600, dist=FP*11, half-size=BODY).
fn project_marker(b: &Body) -> (i64, i64, i64, i64) {
    let d = b.p.z + FP * 11;
    let sx = 320 + b.p.x * 600 / d;
    let sy = 240 - b.p.y * 600 / d;
    let sz = BODY * 600 / d;
    (sx - sz, sy - sz, sz + sz, sz + sz)
}

/// A Rust `Scene` (`{markers:[{x,y,w,h}]}`) for an `.ig` `World` JSON — the cross-check mirror of the
/// `.ig` `View` contract. Total/fail-closed.
pub fn scene_json_of_world(world_json: &str) -> String {
    let parsed: serde_json::Value = serde_json::from_str(world_json).unwrap_or(serde_json::Value::Null);
    let markers: Vec<serde_json::Value> = parsed
        .get("bodies")
        .and_then(|b| b.as_array())
        .map(|arr| {
            arr.iter()
                .map(|b| {
                    let (x, y, w, h) = project_marker(&body_from_json(b));
                    serde_json::json!({ "x": x, "y": y, "w": w, "h": h, "id": body_id(b) })
                })
                .collect()
        })
        .unwrap_or_default();
    serde_json::json!({ "markers": markers }).to_string()
}

/// Render an `.ig` `Scene` JSON (the VM's `View` output — already projected to 2D) as depth-shaded
/// squares. This is the host's ONLY job when both the logic AND the view are `.ig`: draw what the VM
/// projected. Total/fail-closed.
pub fn render_scene_json(scene_json: &str) -> String {
    let parsed: serde_json::Value = serde_json::from_str(scene_json).unwrap_or(serde_json::Value::Null);
    let mut ms: Vec<(i64, i64, i64, i64)> = parsed
        .get("markers")
        .and_then(|m| m.as_array())
        .map(|arr| {
            arr.iter()
                .map(|m| {
                    let g = |k: &str| m.get(k).and_then(|v| v.as_i64()).unwrap_or(0);
                    (g("x"), g("y"), g("w"), g("h"))
                })
                .collect()
        })
        .unwrap_or_default();
    ms.sort_by_key(|m| m.2); // far (smaller) first
    let mut body = String::new();
    for (x, y, w, h) in ms {
        let c = (w * 4).clamp(80, 255);
        body.push_str(&format!(
            "  <rect x=\"{x}\" y=\"{y}\" width=\"{}\" height=\"{}\" rx=\"3\" fill=\"none\" stroke=\"rgb({},{},{})\" stroke-width=\"1.6\"/>\n",
            w.max(0), h.max(0), c * 7 / 10, c / 3, c
        ));
    }
    format!(
        "<svg viewBox=\"0 0 {CANVAS_W} {CANVAS_H}\" xmlns=\"http://www.w3.org/2000/svg\">\n  <rect width=\"{CANVAS_W}\" height=\"{CANVAS_H}\" fill=\"#070510\"/>\n{body}</svg>\n"
    )
}

/// Render an `.ig` `World` JSON (the VM's `Step` output) as the 3D wireframe — so a world produced by
/// the `.ig` reducer on the VM draws through the same path as the Rust demo.
pub fn render_world_json(world_json: &str) -> String {
    let parsed: serde_json::Value = serde_json::from_str(world_json).unwrap_or(serde_json::Value::Null);
    let bodies: Vec<Body> = parsed
        .get("bodies")
        .and_then(|b| b.as_array())
        .map(|arr| arr.iter().map(body_from_json).collect())
        .unwrap_or_default();
    let mut edges: Vec<(i64, i64, i64, i64, i64)> = Vec::new();
    push_cube(&mut edges, V3 { x: 0, y: 0, z: 0 }, BOUND, 110);
    for b in &bodies {
        push_cube(&mut edges, b.p, BODY, 255);
    }
    edges_to_svg(edges)
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

fn edges_to_svg(mut edges: Vec<(i64, i64, i64, i64, i64)>) -> String {
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

fn render(world: &[Body; N]) -> String {
    let mut edges: Vec<(i64, i64, i64, i64, i64)> = Vec::new();
    push_cube(&mut edges, V3 { x: 0, y: 0, z: 0 }, BOUND, 110); // bounding box (faint)
    for b in world.iter() {
        push_cube(&mut edges, b.p, BODY, 255); // bodies (bright)
    }
    edges_to_svg(edges)
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
