# Lab: Native GUI Headless Animation Timeline (v0)

Status: `experimental · lab-only · research · no-canon · no-stable-schema`
Track: `lab-native-gui-headless-animation-timeline-proof-v0`
Card: `LAB-NATIVE-GUI-P5`
Date: 2026-06-06
Proof: 17/17 checks passed (79/79 cumulative) — `run_proof.rb`

---

## 1. Overview

This document presents the implementation and validation proof of a **headless scene animation timeline resolver** (`TimelineResolver`) inside `igniter-lab/igniter-gui-engine`.

Building on top of the P4 hardened state binding layer, this milestone introduces time-based keyframe interpolation over a whitelisted set of easing functions and properties. The resolver processes visual transitions as data, returning a layout-resolved, animated bound scene snapshot at any millisecond offset `t` without spawning active graphics loops.

---

## 2. Updated Directory Structure

The files and artifacts involved in this proof track are:

```
igniter-lab/igniter-gui-engine/
  ├── lib/
  │   ├── timeline_resolver.rb        # (new) time-fraction calculations, color/numeric interpolations, timeline limits
  │   └── ... (P1-P4 classes)
  ├── out/
  │   ├── frame_0ms.json              # bound scene state at start (t=0ms)
  │   ├── frame_250ms.json            # bound scene state at midpoint (t=250ms)
  │   ├── frame_500ms.json            # bound scene state at end (t=500ms)
  │   ├── animation_receipt.json      # animation completion trace mapping lineage
  │   └── ... (P1-P4 outputs)
  └── run_proof.rb                    # (updated) runs the 79-check proof matrix
```

---

## 3. Timeline Interpolation & Easing Math

The `TimelineResolver` evaluates properties over time intervals using standard easing interpolations:

* **Linear**: $f(t) = t$
* **Ease In**: $f(t) = t^2$
* **Ease Out**: $f(t) = t(2 - t)$
* **Ease In Out**:
  $$f(t) = \begin{cases} 2t^2 & t < 0.5 \\ -1 + (4 - 2t)t & t \ge 0.5 \end{cases}$$

### Color Interpolation
For `fill` and `stroke` keys, Hex values (e.g. 3, 4, 6, or 8-digit formats) are parsed into individual RGBA integer components, interpolated lineally via the active eased factor $t$, and formatted back into standard CSS Hex strings, supporting alpha-blending natively.

---

## 4. Safety Gates & Fail-Closed Bounds

To satisfy the **Language Covenant**, the animation engine implements these protection gates:
1. **Easing Whitelist Gate**: Only `linear`, `ease_in`, `ease_out`, and `ease_in_out` are allowed. Other string targets fail closed (NGUI-P5-4).
2. **Target Node Validation**: Animating a node ID not declared in the bound scene tree fails closed (NGUI-P5-5).
3. **Property Whitelist**: Only visually safe attributes can be animated (`opacity`, `transform_translate_x/y`, `transform_scale`, `fill`, `stroke`). Layout structural properties remain locked (NGUI-P5-6).
4. **Keyframe Completeness**: Manifest files must explicitly declare all parameters (NGUI-P5-7).
5. **Timeline Duration Guards (DoS Protection)**: Capped duration at **10,000ms**, delay at **5,000ms**, and total animation span at **15,000ms** to prevent timeline locking or resource leaks (NGUI-P5-8, NGUI-P5-9).
6. **Shape Value Constraints**: Opacity boundaries must reside in `[0.0, 1.0]`, and color strings must pass strict hex matching patterns (NGUI-P5-10).

---

## 5. Proof Matrix Results (79/79 Cumulative PASS)

All 17 checks of the NGUI-P5 matrix pass successfully side-by-side with prior milestones:

| ID | Check | Status | Verification Detail |
|---|---|---|---|
| **NGUI-P5-1** | Prior proof checks remain green | **PASS** | Running P1/P2/P3/P4 checks alongside P5 produces zero regressions. |
| **NGUI-P5-2** | Valid opacity animation emits frame snapshots | **PASS** | Generates frame states at `t=0ms` (opacity 0.0), `t=250ms` (opacity 0.5), and `t=500ms` (opacity 1.0). |
| **NGUI-P5-3** | Valid translate animation emits transform fields | **PASS** | Translating `logo` x-offset from 10 to 50 results in `transform_translate_x: 30.0` at `t=250ms`. |
| **NGUI-P5-4** | Easing whitelist is enforced | **PASS** | Animating with easing `"bounce"` throws ValidationError `NGUI-P5-4`. |
| **NGUI-P5-5** | Unknown target node fails closed | **PASS** | Referencing unknown target node ID throws ValidationError `NGUI-P5-5`. |
| **NGUI-P5-6** | Unsupported animated property fails closed | **PASS** | Animating `"font_size"` throws ValidationError `NGUI-P5-6`. |
| **NGUI-P5-7** | Malformed keyframe fails closed | **PASS** | Manifest missing required keys throws ValidationError `NGUI-P5-7`. |
| **NGUI-P5-8** | Negative duration/delay fails closed | **PASS** | Passing a negative duration value throws ValidationError `NGUI-P5-8`. |
| **NGUI-P5-9** | Excessive timeline span fails closed | **PASS** | Manifest duration >10000ms throws ValidationError `NGUI-P5-9`. |
| **NGUI-P5-10** | Invalid color/opacity values fail closed | **PASS** | Non-hex color `"blue"` or opacity `1.5` throws ValidationError `NGUI-P5-10`. |
| **NGUI-P5-11** | Receipt records diagnostic code & lineage | **PASS** | Success receipt records `SUCCESS` and links VM receipt lineage. |
| **NGUI-P5-12** | Frame snapshots contain no absolute paths | **PASS** | Snapshots contain relative identifiers only. |
| **NGUI-P5-13** | No GPU/windowing runtime loaded | **PASS** | Execution remains fully headless. |
| **NGUI-P5-14** | No VM or contract execution occurs | **PASS** | Verified that VM and Contract libraries are isolated. |
| **NGUI-P5-15** | No streaming or polling introduced | **PASS** | Pure functional, time-offset based resolution requires no clock ticks. |
| **NGUI-P5-16** | igniter-lang/** remains untouched | **PASS** | Mainline codebase is untouched. |
| **NGUI-P5-17** | Compliance markers remain present | **PASS** | Headers check confirms lab compliance tags. |

---

## 6. Key Design Decisions

* **D1 — In-Memory Immutable Snapshots**: Evaluator uses `JSON.parse(JSON.generate(...))` to deep copy bound scene trees. This isolates animation frame computations, keeping the original bound tree immutable.
* **D2 — Safe RGBA Color Blending**: Designed custom hex parsers supporting 3, 4, 6, and 8-digit strings, letting alpha channels blend linearly alongside RGB values.
* **D3 — Pure Functional Playback**: Decoupled timeline ticks from system time. The resolver is a pure mapping function `(scene, manifest, time) -> scene`, allowing developers to test animations deterministically (e.g. forward/reverse playback, timeline scrubbing) by specifying target milliseconds.

---

## 7. Recommendation for LAB-NATIVE-GUI-P6

We recommend moving toward **Headless Vector Renderer Artifact Proof**:
1. Implement a headless vector renderer that translates a bound, animated scene tree (such as `frame_250ms.json`) into drawing primitives (rect, rounded_rect, circle, text).
2. Write a proof output format (e.g. an SVG compiler or vector path output receipt) to represent drawing outputs headlessly.
3. Validate by outputting structured receipt paths representing coordinates, color blends, and dimensions.
