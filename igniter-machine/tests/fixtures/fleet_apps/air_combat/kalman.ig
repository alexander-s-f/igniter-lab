module AirCombatKalman
import AirCombatTypes
import AirCombatVec

-- ============================================================
-- Target tracking — alpha-beta (steady-state Kalman) filter
-- ============================================================
-- State is a `Track` record: estimated position `est`, estimated
-- velocity `vel`, and a scalar covariance proxy `p`.
--
-- One filter step is two record->record transforms:
--   PREDICT: est += vel ; p grows (uncertainty accumulates)
--   UPDATE : correct est/vel toward the measurement by gains a,b ;
--            p shrinks (a measurement reduces uncertainty)
--
-- alpha (position gain) and beta (velocity gain) are fixed-point /100.
-- Here alpha ~ 0.50 (50) and beta ~ 0.10 (10) — tuned for a smooth track.

-- ── PREDICT ─────────────────────────────────────────────────
pure contract TrackPredict {
  input t : Track

  compute est1 = call_contract("VAdd", t.est, t.vel)
  -- uncertainty grows by a fixed process-noise term each tick
  compute p1 = t.p + 20

  compute predicted = { est: est1, vel: t.vel, p: p1 }
  output predicted : Track
}

-- ── UPDATE ──────────────────────────────────────────────────
-- Correct the predicted track toward a noisy measurement.
pure contract TrackUpdate {
  input t : Track
  input m : Measurement

  -- residual = measurement - predicted position
  compute resid = call_contract("VSub", m.pos, t.est)

  -- est += alpha * residual   (alpha = 0.50)
  compute est_corr = call_contract("VScale", resid, 50)
  compute est2 = call_contract("VAdd", t.est, est_corr)

  -- vel += beta * residual    (beta = 0.10)
  compute vel_corr = call_contract("VScale", resid, 10)
  compute vel2 = call_contract("VAdd", t.vel, vel_corr)

  -- a measurement shrinks uncertainty (never below a floor of 10)
  compute p_raw = (t.p * 60) / 100
  compute p2 = if p_raw < 10 { 10 } else { p_raw }

  compute corrected = { est: est2, vel: vel2, p: p2 }
  output corrected : Track
}

-- ── One full predict+update step ────────────────────────────
-- This is the body a fold lambda WANTS to be:
--   fold(measurements, track0, (track, m) -> TrackStep(track, m))
-- See AC-P01 — fold-to-struct is not available, so engine.ig and
-- TrackFold3 below unroll the sequence by hand.
pure contract TrackStep {
  input t : Track
  input m : Measurement

  compute predicted = call_contract("TrackPredict", t)
  compute updated = call_contract("TrackUpdate", predicted, m)
  output updated : Track
}

-- ── Manual fold-to-struct WORKAROUND (3 measurements) ───────
-- PRESSURE AC-P01: this is exactly fold(ms, t0, TrackStep) but the
-- record accumulator cannot be folded today (OOF-COL4), so we unroll.
pure contract TrackFold3 {
  input t0 : Track
  input m1 : Measurement
  input m2 : Measurement
  input m3 : Measurement

  compute t1 = call_contract("TrackStep", t0, m1)
  compute t2 = call_contract("TrackStep", t1, m2)
  compute t3 = call_contract("TrackStep", t2, m3)
  output t3 : Track
}
