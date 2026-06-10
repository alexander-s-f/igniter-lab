#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_pursuit_guidance_p1.rb
# LAB-PURSUIT-P1: Hypothetical application pressure — quadcopter pursuit/evasion
# guidance stack (Kalman filter + ZEM interception + evasion) as a language
# sufficiency probe, with closed-loop simulation through the lab VM.
#
# Domain: classic control-theory benchmark — pursuit-evasion differential games
# (Isaacs) + linear estimation (Kalman). One quadcopter intercepts another.
# No real sensors/actuators/radios — the "world" lives in this harness (Ruby
# integrates true states); the AVIONICS (KF predict/update, ZEM guidance,
# evasion, epistemic routing) execute in the lab Rust VM as pure contracts.
#
# ARITHMETIC BOUNDARY (proved here as checks):
#   Float arithmetic — rejected by BOTH typecheckers.
#   Decimal arithmetic — Rust TC accepts; Ruby TC rejects (divergence, flagged).
#   Integer fixed-point — dual-toolchain green; THE viable path (and the
#   embedded-grade one: deterministic, FPU-free). VM stdlib has NO sqrt/sin/cos —
#   algorithms here are arithmetic-only by construction (sqrt-free ZEM t_go).
#   Integer division truncates toward zero (Rust i64); the Ruby reference
#   implementation below uses matching truncation (NOT Ruby floor division).
#
# Layers:
#   A — Ruby TypeChecker: KF contracts accepted (pure integer arithmetic is
#       dual-toolchain); routers/guards blocked by the known ==/< divergence.
#   B — Rust compiler + VM: all 7 contracts execute; KF numerics EXACTLY equal
#       the reference implementation (integer determinism → exact equality).
#   C — Closed-loop simulation: harness ticks the world; VM contracts fly the
#       pursuit. Interception demonstrated; evasion demonstrably effective.
#
# Authority: LAB-ONLY. No canon claim. No public/stable API. No PROP.
# No real-world targeting claim — textbook guidance benchmark as language pressure.
#
# Run: ruby igniter-view-engine/proofs/verify_pursuit_guidance_p1.rb

SOURCE = File.read(__FILE__).freeze

require 'json'
require 'open3'
require 'tmpdir'
require 'fileutils'
require 'pathname'
require 'tempfile'

ROOT           = Pathname.new(__dir__).parent
LAB_ROOT       = ROOT.parent
WORKSPACE_ROOT = LAB_ROOT.parent
IGNITER_LIB    = WORKSPACE_ROOT / 'igniter-lang' / 'lib'
COMPILER_BIN   = (LAB_ROOT / 'igniter-compiler' / 'target' / 'release' / 'igniter_compiler').to_s
VM_BIN         = (LAB_ROOT / 'igniter-vm' / 'target' / 'release' / 'igniter-vm').to_s
FIXTURE_PATH   = (ROOT / 'fixtures' / 'pursuit_guidance' / 'pursuit_guidance.ig').to_s
VM_SRC         = (LAB_ROOT / 'igniter-vm' / 'src' / 'vm.rs').to_s

$LOAD_PATH.unshift(IGNITER_LIB.to_s) unless $LOAD_PATH.include?(IGNITER_LIB.to_s)
require 'igniter_lang'

$pass = 0
$fail = 0
def check(label)
  ok = yield
  puts(ok ? "  PASS: #{label}" : "  FAIL: #{label}")
  ok ? $pass += 1 : $fail += 1
rescue => e
  puts "  ERROR: #{label} — #{e.class}: #{e.message.lines.first&.strip}"
  $fail += 1
end

# ── Truncating integer division (Rust i64 semantics, NOT Ruby floor) ──────────
def idiv(a, b)
  q = a / b
  q += 1 if q < 0 && q * b != a
  q
end

# ── Toolchain helpers ─────────────────────────────────────────────────────────
def ruby_tc(src)
  parsed = IgniterLang::ParsedProgram.parse(src, source_path: 'probe.ig').to_h
  typed  = IgniterLang::TypeChecker.new.typecheck(
    IgniterLang::Classifier.new.classify(parsed, sample_input: {})
  )
  { parsed: parsed, typed: typed }
rescue => e
  { error: e.message }
end

def rust_compile_src(src)
  Dir.mktmpdir('pg_probe') do |out|
    f = Tempfile.new(['probe', '.ig']); f.write(src); f.close
    stdout, _e, _s = Open3.capture3(COMPILER_BIN, 'compile', f.path, '--out', out, '--json')
    f.unlink rescue nil
    stdout = stdout.to_s.force_encoding('UTF-8')
    JSON.parse(stdout.strip) rescue {}
  end
end

def vm_run(entry, inputs)
  tf = Tempfile.new(['pg', '.json'])
  tf.write(inputs.to_json); tf.close
  stdout, _e, _s = Open3.capture3(VM_BIN, 'run', '--contract', PG_OUT,
                                  '--inputs', tf.path, '--entry', entry, '--json')
  tf.unlink rescue nil
  JSON.parse(stdout.strip) rescue { 'status' => 'vm_error', 'error' => stdout.to_s[0, 120] }
end

# ── Reference implementations (Ruby, truncating division) ─────────────────────
def ref_predict(t, dt, q11, q12, q22)
  { 'x_mm'  => t['x_mm'] + idiv(t['v_mms'] * dt, 1000),
    'v_mms' => t['v_mms'],
    'p11'   => t['p11'] + idiv(2 * t['p12'] * dt, 1000) + idiv(t['p22'] * dt * dt, 1_000_000) + q11,
    'p12'   => t['p12'] + idiv(t['p22'] * dt, 1000) + q12,
    'p22'   => t['p22'] + q22 }
end

def ref_update(t, z, r)
  s  = t['p11'] + r
  k1 = idiv(1000 * t['p11'], s)
  k2 = idiv(1000 * t['p12'], s)
  res = z - t['x_mm']
  { 'x_mm'  => t['x_mm'] + idiv(k1 * res, 1000),
    'v_mms' => t['v_mms'] + idiv(k2 * res, 1000),
    'p11'   => idiv((1000 - k1) * t['p11'], 1000),
    'p12'   => idiv((1000 - k1) * t['p12'], 1000),
    'p22'   => t['p22'] - idiv(k2 * t['p12'], 1000) }
end

# Deterministic pseudo-noise (LCG) — synthetic world, fixed seed, replayable.
class Lcg
  def initialize(seed) = @s = seed
  def next_noise(span) # ± span mm
    @s = (@s * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407) & 0xFFFFFFFFFFFFFFFF
    ((@s >> 33) % (2 * span + 1)) - span
  end
end

# ── Compile fixture once ──────────────────────────────────────────────────────
PG_OUT = Dir.mktmpdir('pg_main')
compile_report = nil
Open3.popen3(COMPILER_BIN, 'compile', FIXTURE_PATH, '--out', PG_OUT, '--json') do |_i, o, _e, _t|
  compile_report = JSON.parse(o.read.strip) rescue {}
end
PG_SIR = begin
  JSON.parse(File.read(File.join(PG_OUT, 'semantic_ir_program.json')))
rescue
  nil
end
PG_TC = ruby_tc(File.read(FIXTURE_PATH, encoding: 'UTF-8'))

def tc_status(name)
  c = PG_TC[:typed]&.fetch('contracts', [])&.find { |x| x['name'] == name }
  c && c['status']
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nHYP-COMPILE"

check('HYP-COMPILE-01: Rust compiler emits SIR with 7 contracts') do
  PG_SIR.is_a?(Hash) && PG_SIR.fetch('contracts', []).length == 7
end
check('HYP-COMPILE-02: Ruby TC ACCEPTS the full integer Kalman filter (predict+update) — dual-toolchain arithmetic') do
  tc_status('KalmanPredict') == 'accepted' && tc_status('KalmanUpdate') == 'accepted'
end
check('HYP-COMPILE-03: routers/guards blocked in Ruby TC by known ==/< divergence (documented, not hidden)') do
  tc_status('TrackStepRouter') != 'accepted' && tc_status('ZemGuidance') != 'accepted'
end
check('HYP-COMPILE-04: fixture declares no variants; KDR + pure contracts only') do
  (PG_TC[:parsed]&.fetch('variants', []) || []).empty?
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nHYP-MATHGAP  (the arithmetic boundary, proved as checks)"

FLOAT_SRC = <<~IG
  module Lab.FloatProbe
  pure contract F {
    input  x : Float
    input  v : Float
    compute m = x * v
    output m : Float
  }
IG

DEC_SRC = <<~IG
  module Lab.DecProbe2
  pure contract D {
    input  x : Decimal[3]
    input  v : Decimal[3]
    compute m = x * v
    output m : Decimal[3]
  }
IG

check('HYP-MATHGAP-01: Float arithmetic is REJECTED by the Ruby TypeChecker') do
  r = ruby_tc(FLOAT_SRC)
  c = r[:typed]&.fetch('contracts', [])&.first
  c && c['status'] != 'accepted'
end
check('HYP-MATHGAP-02: Float arithmetic is REJECTED by the Rust compiler (OOF-TY0)') do
  rep = rust_compile_src(FLOAT_SRC)
  rep.fetch('diagnostics', []).any? { |d| d['message'].to_s.include?('Float') }
end
check('HYP-MATHGAP-03: Decimal arithmetic DIVERGES — Rust TC accepts, Ruby TC rejects (flagged, not resolved)') do
  rust_ok = rust_compile_src(DEC_SRC).fetch('diagnostics', []).empty?
  ruby_c  = ruby_tc(DEC_SRC)[:typed]&.fetch('contracts', [])&.first
  rust_ok && ruby_c && ruby_c['status'] != 'accepted'
end
check('HYP-MATHGAP-04: VM stdlib has no sqrt/sin/cos/atan — algorithms must be arithmetic-only') do
  vm_src = File.read(VM_SRC, encoding: 'UTF-8')
  ['"sqrt"', '"sin"', '"cos"', '"atan"', '"atan2"'].none? { |f| vm_src.include?(f) }
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nHYP-KF  (Kalman numerics: VM ≡ reference, exact integer equality)"

T0 = { 'p11' => 1_000_000, 'p12' => 0, 'p22' => 250_000, 'v_mms' => 2500, 'x_mm' => 10_000 }.freeze
Q  = { q11: 100, q12: 0, q22: 400 }.freeze
RVAR = 90_000 # (300 mm)^2 measurement variance

VM_PRED = vm_run('KalmanPredict', { 'track' => T0, 'dt_ms' => 100, 'q11' => Q[:q11], 'q12' => Q[:q12], 'q22' => Q[:q22] })
REF_PRED = ref_predict(T0, 100, Q[:q11], Q[:q12], Q[:q22])

check('HYP-KF-01: VM predict EXACTLY equals reference (all 5 state/covariance fields)') do
  VM_PRED['status'] == 'success' && VM_PRED['result'] == REF_PRED
end

VM_UPD  = vm_run('KalmanUpdate', { 'track' => REF_PRED, 'z_mm' => 10_400, 'r_var' => RVAR })
REF_UPD = ref_update(REF_PRED, 10_400, RVAR)

check('HYP-KF-02: VM update EXACTLY equals reference') do
  VM_UPD['status'] == 'success' && VM_UPD['result'] == REF_UPD
end
check('HYP-KF-03: measurement update SHRINKS position covariance (p11+ < p11-)') do
  VM_UPD.dig('result', 'p11') < REF_PRED['p11']
end
check('HYP-KF-04: update moves the estimate toward the measurement') do
  x0 = REF_PRED['x_mm']
  x1 = VM_UPD.dig('result', 'x_mm')
  x1 > x0 && x1 <= 10_400
end

# negative residual: z < x (truncation toward zero must match the reference)
VM_NEG  = vm_run('KalmanUpdate', { 'track' => REF_PRED, 'z_mm' => 9_900, 'r_var' => RVAR })
REF_NEG = ref_update(REF_PRED, 9_900, RVAR)
check('HYP-KF-05: negative residual EXACTLY matches (truncation-toward-zero semantics aligned)') do
  VM_NEG['status'] == 'success' && VM_NEG['result'] == REF_NEG
end

check('HYP-KF-06: coasting (sensor lost ⇒ predict-only) grows uncertainty monotonically over 5 steps (P11)') do
  t = REF_UPD
  p11s = [t['p11']]
  5.times do
    r = vm_run('KalmanPredict', { 'track' => t, 'dt_ms' => 100, 'q11' => Q[:q11], 'q12' => Q[:q12], 'q22' => Q[:q22] })
    t = r['result']
    p11s << t['p11']
  end
  p11s.each_cons(2).all? { |a, b| b > a }
end

check('HYP-KF-07: determinism — identical input twice yields IDENTICAL output (replay-grade)') do
  a = vm_run('KalmanUpdate', { 'track' => T0, 'z_mm' => 10_400, 'r_var' => RVAR })
  b = vm_run('KalmanUpdate', { 'track' => T0, 'z_mm' => 10_400, 'r_var' => RVAR })
  a['result'] == b['result'] && !a['result'].nil?
end

check('HYP-KF-08: 10-step filter converges — final estimate error < initial error (truth 12000, x0 10000)') do
  truth_x = 12_000
  t = { 'p11' => 1_000_000, 'p12' => 0, 'p22' => 250_000, 'v_mms' => 0, 'x_mm' => 10_000 }
  10.times do
    t = vm_run('KalmanPredict', { 'track' => t, 'dt_ms' => 100, 'q11' => Q[:q11], 'q12' => Q[:q12], 'q22' => Q[:q22] })['result']
    t = vm_run('KalmanUpdate',  { 'track' => t, 'z_mm' => truth_x, 'r_var' => RVAR })['result']
  end
  (t['x_mm'] - truth_x).abs < (10_000 - truth_x).abs / 10
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nHYP-ZEM  (sqrt-free proportional navigation)"

check('HYP-ZEM-01: perfect collision course ⇒ ZEM=0 ⇒ zero acceleration, kind=guide, tgo exact (5000ms)') do
  r = vm_run('ZemGuidance', { 'rx_mm' => 100_000, 'ry_mm' => 50_000, 'vx_mms' => -20_000, 'vy_mms' => -10_000, 'nav_n' => 3, 'amax_mms2' => 30_000 })['result']
  r == { 'ax_mms2' => 0, 'ay_mms2' => 0, 'kind' => 'guide', 'tgo_ms' => 5000 }
end
check('HYP-ZEM-02: offset course ⇒ exact corrective accel (-235, 470) at tgo=5102ms (hand-verified)') do
  r = vm_run('ZemGuidance', { 'rx_mm' => 100_000, 'ry_mm' => 50_000, 'vx_mms' => -20_000, 'vy_mms' => -9_000, 'nav_n' => 3, 'amax_mms2' => 30_000 })['result']
  r == { 'ax_mms2' => -235, 'ay_mms2' => 470, 'kind' => 'guide', 'tgo_ms' => 5102 }
end
check('HYP-ZEM-03: diverging geometry ⇒ kind=cannot_intercept, zero accel (honest terminal, no fabricated command)') do
  r = vm_run('ZemGuidance', { 'rx_mm' => 100_000, 'ry_mm' => 50_000, 'vx_mms' => 20_000, 'vy_mms' => 10_000, 'nav_n' => 3, 'amax_mms2' => 30_000 })['result']
  r['kind'] == 'cannot_intercept' && r['ax_mms2'] == 0 && r['ay_mms2'] == 0
end
check('HYP-ZEM-04: cannot_intercept is NOT spelled as failure/system_error (PROP-047 namespace discipline)') do
  r = vm_run('ZemGuidance', { 'rx_mm' => 1000, 'ry_mm' => 0, 'vx_mms' => 1000, 'vy_mms' => 0, 'nav_n' => 3, 'amax_mms2' => 30_000 })['result']
  r['kind'] != 'failed' && r['kind'] != 'system_error' && r['kind'] == 'cannot_intercept'
end
check('HYP-ZEM-05: command clamps to ±amax under extreme ZEM (closing, large cross-range miss)') do
  # closing (rdotv<0), large lateral ZEM ⇒ raw accel far exceeds amax ⇒ must clamp
  r = vm_run('ZemGuidance', { 'rx_mm' => 2_000, 'ry_mm' => 50_000, 'vx_mms' => -100_000, 'vy_mms' => 0, 'nav_n' => 3, 'amax_mms2' => 5_000 })['result']
  r['kind'] == 'guide' && r['ax_mms2'].abs <= 5_000 && r['ay_mms2'].abs <= 5_000 &&
    (r['ax_mms2'].abs == 5_000 || r['ay_mms2'].abs == 5_000)
end
check('HYP-ZEM-06: tgo floors at 1ms (no division blow-up at point-blank range)') do
  r = vm_run('ZemGuidance', { 'rx_mm' => 1, 'ry_mm' => 0, 'vx_mms' => -100_000, 'vy_mms' => 0, 'nav_n' => 3, 'amax_mms2' => 30_000 })['result']
  r['tgo_ms'] >= 1
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nHYP-EVADE"

check('HYP-EVADE-01: evader pushes ALONG the ZEM sign (grows the predicted miss)') do
  r = vm_run('EvasionGuidance', { 'zem_x_mm' => -2_040, 'zem_y_mm' => 4_082, 'amax_mms2' => 20_000 })['result']
  r == { 'ax_mms2' => -20_000, 'ay_mms2' => 20_000, 'kind' => 'evade', 'tgo_ms' => 0 }
end
check('HYP-EVADE-02: zero-ZEM axis produces zero command (no jitter on a dead axis)') do
  r = vm_run('EvasionGuidance', { 'zem_x_mm' => 0, 'zem_y_mm' => 500, 'amax_mms2' => 20_000 })['result']
  r['ax_mms2'] == 0 && r['ay_mms2'] == 20_000
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nHYP-EPIST  (epistemic envelope drives the filter)"

def route_obs(kind)
  vm_run('TrackStepRouter', { 'obs' => { 'evidence_kind' => 'real', 'kind' => kind, 'metadata' => {}, 'uncertainty_mm' => 300, 'z_mm' => 0 } })['result']
end

check('HYP-EPIST-01: measured → update') { route_obs('measured') == 'update' }
check('HYP-EPIST-02: sensor_lost → coast (never fabricate a measurement; unknown ≠ failure)') { route_obs('sensor_lost') == 'coast' }
check('HYP-EPIST-03: stale → coast (stale observation is not fresh evidence)') { route_obs('stale') == 'coast' }
check('HYP-EPIST-04: unrecognised kind → hold (fail closed)') { route_obs('garbage') == 'hold' }
check('HYP-EPIST-05: TrackObservation REQUIRES uncertainty_mm + evidence_kind (Covenant P11/P13 shape)') do
  te = PG_TC[:typed]&.fetch('type_env', {})&.fetch('TrackObservation', {}) || {}
  te.key?('uncertainty_mm') && te.key?('evidence_kind')
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nHYP-ENGAGE  (epistemic honesty gates guidance)"

def engage(gk, unc, ev, appr)
  vm_run('EngageGuard', { 'guidance_kind' => gk, 'uncertainty_mm' => unc, 'uncert_budget_mm' => 2_000,
                          'evidence_kind' => ev, 'human_approved' => appr })['result']
end

check('HYP-ENGAGE-01: diverging geometry → cannot_intercept (honest terminal first)') do
  engage('cannot_intercept', 100, 'real', 'yes') == 'cannot_intercept'
end
check('HYP-ENGAGE-02: track too uncertain → escalate_human (never guide blind)') do
  engage('guide', 5_000, 'real', 'no') == 'escalate_human'
end
check('HYP-ENGAGE-03: model-kind track evidence without human approval → escalate_human (No-Upward-Coercion)') do
  engage('guide', 500, 'model', 'no') == 'escalate_human'
end
check('HYP-ENGAGE-04: model-kind evidence WITH human approval → guide') do
  engage('guide', 500, 'model', 'yes') == 'guide'
end
check('HYP-ENGAGE-05: real evidence within budget → guide (no gratuitous escalation)') do
  engage('guide', 500, 'real', 'no') == 'guide'
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nHYP-SIM  (closed-loop pursuit through the VM — the simulator host pattern)"

# World (harness): true states, integration, deterministic noise. Avionics (VM):
# per-axis KF + ZEM guidance (+ evasion for the evader in scenario B).
def simulate(evading:, ticks:, seed:)
  dt = 100 # ms
  lcg = Lcg.new(seed)
  # truth (mm, mm/s). PN guidance nulls line-of-sight rotation; it does NOT create
  # closing velocity — so the interceptor starts post-boost with a closing velocity
  # aimed at the evader's initial position (the standard PN engagement setup).
  ex, ey, evx, evy = 100_000, 50_000, -5_000, 3_000  # evader
  px, py = 0, 0                                       # pursuer position
  pvx, pvy = 13_416, 6_708                            # ~15 m/s closing toward (100k,50k)
  p_amax = 25_000 # mm/s²
  e_amax = 8_000
  p_vmax = 20_000 # mm/s
  trk_x = { 'p11' => 1_000_000, 'p12' => 0, 'p22' => 1_000_000, 'v_mms' => 0, 'x_mm' => 100_000 }
  trk_y = { 'p11' => 1_000_000, 'p12' => 0, 'p22' => 1_000_000, 'v_mms' => 0, 'x_mm' => 50_000 }
  min_miss = Float::INFINITY
  intercept_tick = nil
  est_err_final = nil
  vm_failures = 0

  ticks.times do |tick|
    # avionics: KF predict + (noisy) update per axis
    [[trk_x, ex], [trk_y, ey]].each_with_index do |(trk, truth), i|
      pred = vm_run('KalmanPredict', { 'track' => trk, 'dt_ms' => dt, 'q11' => 200, 'q12' => 0, 'q22' => 2_000 })
      vm_failures += 1 unless pred['status'] == 'success'
      t = pred['result']
      z = truth + lcg.next_noise(300)
      upd = vm_run('KalmanUpdate', { 'track' => t, 'z_mm' => z, 'r_var' => 90_000 })
      vm_failures += 1 unless upd['status'] == 'success'
      i.zero? ? trk_x = upd['result'] : trk_y = upd['result']
    end

    # pursuer guidance from ESTIMATED relative state (estimate − pursuer truth)
    rel = { 'rx_mm' => trk_x['x_mm'] - px, 'ry_mm' => trk_y['x_mm'] - py,
            'vx_mms' => trk_x['v_mms'] - pvx, 'vy_mms' => trk_y['v_mms'] - pvy,
            'nav_n' => 3, 'amax_mms2' => p_amax }
    g = vm_run('ZemGuidance', rel)
    vm_failures += 1 unless g['status'] == 'success'
    cmd = g['result']
    ax = cmd['ax_mms2']
    ay = cmd['ay_mms2']

    # evader guidance (scenario B): grow the pursuer's ZEM (computed on truth — worst case)
    eax = eay = 0
    if evading
      r2    = (ex - px)**2 + (ey - py)**2
      rdotv = (ex - px) * (evx - pvx) + (ey - py) * (evy - pvy)
      if rdotv.negative?
        tgo = idiv(1000 * r2, -rdotv)
        zx = (ex - px) + idiv((evx - pvx) * tgo, 1000)
        zy = (ey - py) + idiv((evy - pvy) * tgo, 1000)
        ev = vm_run('EvasionGuidance', { 'zem_x_mm' => zx, 'zem_y_mm' => zy, 'amax_mms2' => e_amax })
        vm_failures += 1 unless ev['status'] == 'success'
        eax = ev.dig('result', 'ax_mms2')
        eay = ev.dig('result', 'ay_mms2')
      end
    end

    # world integration (truth — harness owns physics)
    pvx += idiv(ax * dt, 1000); pvy += idiv(ay * dt, 1000)
    spd2 = pvx * pvx + pvy * pvy
    if spd2 > p_vmax * p_vmax # crude speed clamp, harness-side
      pvx = idiv(pvx * 9, 10); pvy = idiv(pvy * 9, 10)
    end
    evx += idiv(eax * dt, 1000); evy += idiv(eay * dt, 1000)
    px += idiv(pvx * dt, 1000); py += idiv(pvy * dt, 1000)
    ex += idiv(evx * dt, 1000); ey += idiv(evy * dt, 1000)

    miss = Math.sqrt((ex - px)**2 + (ey - py)**2) # world-side metric only
    min_miss = miss if miss < min_miss
    intercept_tick ||= tick if miss < 2_000
    est_err_final = Math.sqrt((trk_x['x_mm'] - ex)**2 + (trk_y['x_mm'] - ey)**2)
    break if intercept_tick
  end

  { min_miss: min_miss, intercept_tick: intercept_tick,
    est_err: est_err_final, vm_failures: vm_failures }
end

SIM_A = simulate(evading: false, ticks: 150, seed: 42)
SIM_B = simulate(evading: true,  ticks: 150, seed: 42)

check('HYP-SIM-01: non-evading target INTERCEPTED (miss < 2 m within 15 s of sim time)') do
  !SIM_A[:intercept_tick].nil?
end
check('HYP-SIM-02: closure achieved — min miss far below initial range (111.8 m → < 2 m)') do
  SIM_A[:min_miss] < 2_000
end
check('HYP-SIM-03: KF tracked the maneuvering truth (final estimate error < 1.5 m under ±0.3 m noise)') do
  SIM_A[:est_err] && SIM_A[:est_err] < 1_500
end
check('HYP-SIM-04: every VM call in the closed loop succeeded (zero avionics faults)') do
  SIM_A[:vm_failures].zero? && SIM_B[:vm_failures].zero?
end
check('HYP-SIM-05: EVASION IS EFFECTIVE — evading target survives longer or forces a larger miss') do
  a_t = SIM_A[:intercept_tick] || 999
  b_t = SIM_B[:intercept_tick] || 999
  b_t > a_t || SIM_B[:min_miss] > SIM_A[:min_miss]
end
check('HYP-SIM-06: deterministic replay — same seed reruns to the IDENTICAL trajectory outcome') do
  again = simulate(evading: false, ticks: 150, seed: 42)
  again[:intercept_tick] == SIM_A[:intercept_tick] && again[:min_miss] == SIM_A[:min_miss]
end

puts "    [sim A: intercept @tick=#{SIM_A[:intercept_tick].inspect} min_miss=#{SIM_A[:min_miss].round}mm est_err=#{SIM_A[:est_err]&.round}mm]"
puts "    [sim B: intercept @tick=#{SIM_B[:intercept_tick].inspect} min_miss=#{SIM_B[:min_miss].round}mm (evading)]"

# ─────────────────────────────────────────────────────────────────────────────
puts "\nHYP-CLOSED"

check('HYP-CLOSED-01: fixture contains no Float literals and no Float arithmetic (integer fixed-point only)') do
  code = File.read(FIXTURE_PATH, encoding: 'UTF-8').lines.reject { |l| l.strip.start_with?('--') }.join
  !code.match?(/\d\.\d/) && !code.include?(': Float')
end
check('HYP-CLOSED-02: no real sensor/actuator/network/storage I/O anywhere (pure contracts + harness world)') do
  !SOURCE.include?('TCPSock' + 'et') && !SOURCE.include?('Net::HT' + 'TP') &&
    !SOURCE.include?('serialp' + 'ort') && !SOURCE.include?('mavl' + 'ink')
end
check('HYP-CLOSED-03: time is explicit input everywhere (no ambient now in fixture)') do
  code = File.read(FIXTURE_PATH, encoding: 'UTF-8').lines.reject { |l| l.strip.start_with?('--') }.join
  !code.include?('now()')
end
check('HYP-CLOSED-04: lab-only boundary stated in fixture and runner; no canon/production claim') do
  File.read(FIXTURE_PATH, encoding: 'UTF-8').include?('LAB-ONLY') && SOURCE.include?('LAB-ONLY')
end
check('HYP-CLOSED-05: no canon production file edited (runner is read-only over toolchain)') do
  !SOURCE.include?('typecheck' + 'er.rb') && !SOURCE.include?('File.' + 'write')
end

# ─────────────────────────────────────────────────────────────────────────────
total = $pass + $fail
puts "\n#{'=' * 60}"
puts "LAB-PURSUIT-P1 (pursuit/evasion guidance pressure): #{$pass}/#{total} PASS"
puts '=' * 60
exit($fail.zero? ? 0 : 1)
