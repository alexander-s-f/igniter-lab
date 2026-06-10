module Lab.Hypothetical.PursuitGuidance

-- LAB-PURSUIT-P1: Hypothetical application pressure — quadcopter pursuit/evasion
-- guidance stack as a language sufficiency probe (Kalman filter + interception +
-- evasion), with a future Igniter simulator in view.
--
-- Domain: classic control-theory benchmark — pursuit-evasion differential games
-- (Isaacs 1965) + linear state estimation (Kalman 1960). One quadcopter (pursuer)
-- intercepts another (evader). This is the Covenant's native habitat: its own
-- examples are drone sensors, PositionEstimate{uncertainty_m}, DispatchReceipt.
--
-- ARITHMETIC BOUNDARY (probed 2026-06-10):
--   Float arithmetic — REJECTED by BOTH typecheckers (operators are Integer-typed).
--   Decimal arithmetic — Rust TC accepts, Ruby TC rejects (divergence; flagged).
--   Integer arithmetic — dual-toolchain green. NO sqrt/sin/cos/abs in VM stdlib.
-- Therefore: INTEGER FIXED-POINT throughout (embedded-grade, deterministic, FPU-free):
--   position mm | velocity mm/s | time ms | accel mm/s² | gains milli (x1000)
-- All algorithms below are arithmetic-only by construction:
--   * per-axis 2-state constant-velocity Kalman filter (explicit covariance);
--   * ZEM proportional navigation WITHOUT sqrt: t_go = r² / (−r·v);
--   * bang-bang evasion from ZEM sign.
-- Integer division truncates toward zero (Rust i64 semantics) — the proof's
-- reference implementation must match that, not Ruby floor division.
--
-- EPISTEMIC SURFACE (composes with LAB-EPISTEMIC-OUTCOME P1..P4):
--   TrackObservation is a KDR envelope: "measured" | "sensor_lost" | "stale".
--   sensor_lost is NOT a failure — the filter COASTS (predict-only, covariance
--   grows; uncertainty is never silently discarded — Covenant P11).
--   EngageGuard routes: diverging geometry → "cannot_intercept" (honest terminal,
--   not failure); uncertainty above budget → "escalate_human"; model-kind track
--   evidence without human approval → "escalate_human" (No-Upward-Coercion).
--
-- KDR convention only. No variant/match. No real sensors, actuators, radios,
-- network, storage, or any I/O — pure contracts; the world lives in the proof
-- harness. dt/time are explicit inputs (no ambient now() — Covenant Law 6).
-- No real-world targeting claim: textbook guidance benchmark as language pressure.
--
-- Authority: LAB-ONLY. No canon claim. No public/stable API. No PROP.

-- ── Types ──────────────────────────────────────────────────────────────────────

type AxisTrack {
  p11:   Integer,
  p12:   Integer,
  p22:   Integer,
  v_mms: Integer,
  x_mm:  Integer
}

type TrackObservation {
  evidence_kind:  String,
  kind:           String,
  metadata:       Map[String, String],
  uncertainty_mm: Integer,
  z_mm:           Integer
}

type GuidanceCmd {
  ax_mms2: Integer,
  ay_mms2: Integer,
  kind:    String,
  tgo_ms:  Integer
}

-- ── Kalman: per-axis predict (constant-velocity model, fixed-point) ────────────
-- x' = x + v*dt/1000
-- P' = F P Fᵀ + Q  (CV model):
--   p11' = p11 + 2*p12*dt/1000 + p22*dt²/10⁶ + q11
--   p12' = p12 + p22*dt/1000 + q12
--   p22' = p22 + q22
-- Coasting (sensor lost) is exactly: predict without update — covariance grows.

pure contract KalmanPredict {
  input  track : AxisTrack
  input  dt_ms : Integer
  input  q11   : Integer
  input  q12   : Integer
  input  q22   : Integer
  compute x_pred   = track.x_mm + track.v_mms * dt_ms / 1000
  compute p11_pred = track.p11 + 2 * track.p12 * dt_ms / 1000 + track.p22 * dt_ms * dt_ms / 1000000 + q11
  compute p12_pred = track.p12 + track.p22 * dt_ms / 1000 + q12
  compute p22_pred = track.p22 + q22
  compute next = { p11: p11_pred, p12: p12_pred, p22: p22_pred, v_mms: track.v_mms, x_mm: x_pred }
  output next : AxisTrack
}

-- ── Kalman: per-axis measurement update (gains in milli) ───────────────────────
-- S = p11 + R ; k1 = 1000*p11/S ; k2 = 1000*p12/S
-- x⁺ = x + k1*(z−x)/1000 ; v⁺ = v + k2*(z−x)/1000
-- p11⁺ = (1000−k1)*p11/1000 ; p12⁺ = (1000−k1)*p12/1000 ; p22⁺ = p22 − k2*p12/1000

pure contract KalmanUpdate {
  input  track : AxisTrack
  input  z_mm  : Integer
  input  r_var : Integer
  compute s_inn  = track.p11 + r_var
  compute k1_mil = 1000 * track.p11 / s_inn
  compute k2_mil = 1000 * track.p12 / s_inn
  compute resid  = z_mm - track.x_mm
  compute x_upd  = track.x_mm + k1_mil * resid / 1000
  compute v_upd  = track.v_mms + k2_mil * resid / 1000
  compute p11_u  = (1000 - k1_mil) * track.p11 / 1000
  compute p12_u  = (1000 - k1_mil) * track.p12 / 1000
  compute p22_u  = track.p22 - k2_mil * track.p12 / 1000
  compute next = { p11: p11_u, p12: p12_u, p22: p22_u, v_mms: v_upd, x_mm: x_upd }
  output next : AxisTrack
}

-- ── Epistemic step router: observation kind drives filter behavior ─────────────
-- "measured"     → "update"  (predict + correct)
-- "stale"        → "coast"   (predict only; stale ≠ fresh evidence)
-- "sensor_lost"  → "coast"   (unknown external state analog: never fabricate z)
-- anything else  → "hold"    (fail closed)

pure contract TrackStepRouter {
  input  obs : TrackObservation
  compute is_meas  = obs.kind == "measured"
  compute is_stale = obs.kind == "stale"
  compute is_lost  = obs.kind == "sensor_lost"
  compute action =
    if is_meas { "update" } else {
      if is_stale { "coast" } else {
        if is_lost { "coast" } else { "hold" }
      }
    }
  output action : String
}

-- ── ZEM proportional navigation (sqrt-free, fixed-point) ──────────────────────
-- Relative state r = target − pursuer (mm), v = v_t − v_p (mm/s).
-- closing test:  r·v < 0  (approaching)
-- t_go_ms = 1000 * r² / (−r·v)
-- ZEM_x   = rx + vx * t_go/1000  (predicted miss at t_go, mm)
-- a_cmd_x = N * ZEM_x * 10⁶ / t_go²  (mm/s²), N = nav constant (typ. 3)
-- Diverging geometry (r·v ≥ 0) → kind "cannot_intercept": an honest terminal,
-- NOT a failure and NOT a fabricated command.

pure contract ZemGuidance {
  input  rx_mm  : Integer
  input  ry_mm  : Integer
  input  vx_mms : Integer
  input  vy_mms : Integer
  input  nav_n  : Integer
  input  amax_mms2 : Integer
  compute r2     = rx_mm * rx_mm + ry_mm * ry_mm
  compute rdotv  = rx_mm * vx_mms + ry_mm * vy_mms
  compute closing = rdotv < 0
  compute tgo_raw = if closing { 1000 * r2 / (0 - rdotv) } else { 0 }
  compute tgo_ms  = if tgo_raw < 1 { 1 } else { tgo_raw }
  compute zem_x  = rx_mm + vx_mms * tgo_ms / 1000
  compute zem_y  = ry_mm + vy_mms * tgo_ms / 1000
  compute ax_raw = nav_n * zem_x * 1000000 / (tgo_ms * tgo_ms)
  compute ay_raw = nav_n * zem_y * 1000000 / (tgo_ms * tgo_ms)
  compute neg_amax = 0 - amax_mms2
  compute ax_cl  = if ax_raw > amax_mms2 { amax_mms2 } else { if ax_raw < neg_amax { neg_amax } else { ax_raw } }
  compute ay_cl  = if ay_raw > amax_mms2 { amax_mms2 } else { if ay_raw < neg_amax { neg_amax } else { ay_raw } }
  compute kind   = if closing { "guide" } else { "cannot_intercept" }
  compute ax_out = if closing { ax_cl } else { 0 }
  compute ay_out = if closing { ay_cl } else { 0 }
  compute cmd = { ax_mms2: ax_out, ay_mms2: ay_out, kind: kind, tgo_ms: tgo_ms }
  output cmd : GuidanceCmd
}

-- ── Evasion: bang-bang lateral push against the pursuer's predicted intercept ──
-- The evader steers to GROW the pursuer's zero-effort-miss: accelerate along the
-- sign of ZEM (push the miss further out). Pure arithmetic sign logic.

pure contract EvasionGuidance {
  input  zem_x_mm : Integer
  input  zem_y_mm : Integer
  input  amax_mms2 : Integer
  compute neg_amax = 0 - amax_mms2
  compute ax = if zem_x_mm > 0 { amax_mms2 } else { if zem_x_mm < 0 { neg_amax } else { 0 } }
  compute ay = if zem_y_mm > 0 { amax_mms2 } else { if zem_y_mm < 0 { neg_amax } else { 0 } }
  compute cmd = { ax_mms2: ax, ay_mms2: ay, kind: "evade", tgo_ms: 0 }
  output cmd : GuidanceCmd
}

-- ── Engagement gate: epistemic honesty before guidance is trusted ─────────────
--   geometry "cannot_intercept"            → "cannot_intercept" (honest terminal)
--   track uncertainty above budget         → "escalate_human" (do not guide blind)
--   model-kind evidence, no human approval → "escalate_human" (No-Upward-Coercion)
--   otherwise                              → "guide"

pure contract EngageGuard {
  input  guidance_kind   : String
  input  uncertainty_mm  : Integer
  input  uncert_budget_mm : Integer
  input  evidence_kind   : String
  input  human_approved  : String
  compute no_geom   = guidance_kind == "cannot_intercept"
  compute too_blur  = uncertainty_mm > uncert_budget_mm
  compute ev_model  = evidence_kind == "model"
  compute approved  = human_approved == "yes"
  compute action =
    if no_geom { "cannot_intercept" } else {
      if too_blur { "escalate_human" } else {
        if ev_model {
          if approved { "guide" } else { "escalate_human" }
        } else { "guide" }
      }
    }
  output action : String
}

-- ── Inspector: map chain over observation metadata ─────────────────────────────

pure contract ObservationInspector {
  input  obs      : TrackObservation
  compute src_opt = map_get(obs.metadata, "sensor_id")
  compute sensor  = or_else(src_opt, "unknown_sensor")
  output  sensor  : String
}
