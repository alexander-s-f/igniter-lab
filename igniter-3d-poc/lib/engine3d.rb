# igniter-lab/igniter-3d-poc/lib/engine3d.rb
# frozen_string_literal: true
#
# Status: experimental · lab-only · no-canon · no-stable-schema · no-performance-claim · POC
#
# A HEADLESS, DETERMINISTIC 3D core, built in the Igniter discipline (pure transform,
# fail-closed, fact/receipt-shaped, no GPU/window/network). It proves the claim that the
# Igniter model — `(world, input, dt) -> world'` + a deterministic projection to a frame —
# can express a 3D game loop: the same seed + the same tick sequence yields byte-identical
# frames (deterministic lockstep / replay / time-travel — the real differentiator for games).
#
# This is the PROJECTION/RENDER half. The igniter-machine is the deterministic STATE kernel:
# world state is a content-addressed fact (capsule), a tick is a pure dispatch, a frame is a
# receipted projection of that state. No GPU here — output is an SVG wireframe artifact.

require "json"
require "digest"

module Igniter3D
  class ValidationError < StandardError; end

  # ── 4x4 matrix math (row-major, length-16 arrays) ─────────────────────────
  module M
    module_function

    def identity
      [1.0, 0, 0, 0,  0, 1.0, 0, 0,  0, 0, 1.0, 0,  0, 0, 0, 1.0]
    end

    def mul(a, b)
      r = Array.new(16, 0.0)
      4.times do |i|
        4.times do |j|
          s = 0.0
          4.times { |k| s += a[i * 4 + k] * b[k * 4 + j] }
          r[i * 4 + j] = s
        end
      end
      r
    end

    def rot_x(t)
      c = Math.cos(t); s = Math.sin(t)
      [1, 0, 0, 0,  0, c, -s, 0,  0, s, c, 0,  0, 0, 0, 1]
    end

    def rot_y(t)
      c = Math.cos(t); s = Math.sin(t)
      [c, 0, s, 0,  0, 1, 0, 0,  -s, 0, c, 0,  0, 0, 0, 1]
    end

    def rot_z(t)
      c = Math.cos(t); s = Math.sin(t)
      [c, -s, 0, 0,  s, c, 0, 0,  0, 0, 1, 0,  0, 0, 0, 1]
    end

    def translate(x, y, z)
      [1, 0, 0, x,  0, 1, 0, y,  0, 0, 1, z,  0, 0, 0, 1]
    end

    # Perspective projection (OpenGL-style; clip space, w = -z_eye).
    def perspective(fov_deg, aspect, near, far)
      raise ValidationError, "fov out of range" unless fov_deg > 0 && fov_deg < 180
      raise ValidationError, "near/far invalid" unless near > 0 && far > near
      f = 1.0 / Math.tan(fov_deg * Math::PI / 360.0)
      [f / aspect, 0, 0, 0,
       0, f, 0, 0,
       0, 0, (far + near) / (near - far), (2 * far * near) / (near - far),
       0, 0, -1, 0]
    end

    # Transform a point -> [x, y, z, w] (w not yet divided).
    def transform(m, x, y, z)
      [m[0] * x + m[1] * y + m[2] * z + m[3],
       m[4] * x + m[5] * y + m[6] * z + m[7],
       m[8] * x + m[9] * y + m[10] * z + m[11],
       m[12] * x + m[13] * y + m[14] * z + m[15]]
    end
  end

  # A unit cube centred at the origin: 8 vertices, 12 edges.
  CUBE_VERTS = [
    [-0.5, -0.5, -0.5], [0.5, -0.5, -0.5], [0.5, 0.5, -0.5], [-0.5, 0.5, -0.5],
    [-0.5, -0.5, 0.5], [0.5, -0.5, 0.5], [0.5, 0.5, 0.5], [-0.5, 0.5, 0.5]
  ].freeze
  CUBE_EDGES = [
    [0, 1], [1, 2], [2, 3], [3, 0], # back face
    [4, 5], [5, 6], [6, 7], [7, 4], # front face
    [0, 4], [1, 5], [2, 6], [3, 7]  # connectors
  ].freeze

  # ── World state: a content-addressed snapshot of entities (the "capsule") ──
  class World
    attr_reader :tick, :entities

    QUANTUM = 1_000_000 # quantize angles -> deterministic across platforms (fixed-point lockstep)

    def self.cube_demo
      new(0, [{
        "id" => "cube",
        "mesh" => "cube",
        "pos" => [0.0, 0.0, 0.0],
        "rot" => [0.3, 0.5, 0.0],
        "ang_vel" => [0.0, 0.15, 0.0]
      }])
    end

    def initialize(tick, entities)
      @tick = tick
      @entities = entities
    end

    # The deterministic update: `(world, dt) -> world'`. Pure, no IO. Rotation advances by
    # angular velocity; angles are quantized to a fixed grid so the evolution is reproducible
    # bit-for-bit (the basis of lockstep netcode / replays).
    def step(dt)
      next_entities = @entities.map do |e|
        rot = e["rot"].each_with_index.map do |r, i|
          q = ((r + e["ang_vel"][i] * dt) * QUANTUM).round
          q.to_f / QUANTUM
        end
        e.merge("rot" => rot)
      end
      World.new(@tick + 1, next_entities)
    end

    # A stable digest of world state (a fact identity — like a machine capsule's content_digest).
    def digest
      "sha256:#{Digest::SHA256.hexdigest(JSON.generate(@entities))}"
    end
  end

  # ── Camera + projection -> screen-space (integer pixels = deterministic frame) ──
  class Camera
    def initialize(width: 400, height: 400, eye_z: 4.0, fov: 60.0, near: 0.1, far: 100.0)
      @w = width
      @h = height
      @view = M.translate(0.0, 0.0, -eye_z) # camera at +eye_z looking down -z
      @proj = M.perspective(fov, width.to_f / height, near, far)
    end

    def model_matrix(e)
      m = M.translate(*e["pos"])
      m = M.mul(m, M.rot_y(e["rot"][1]))
      m = M.mul(m, M.rot_x(e["rot"][0]))
      m = M.mul(m, M.rot_z(e["rot"][2]))
      m
    end

    # Project a world into per-entity screen points (rounded to int pixels) + edges. A vertex
    # behind the camera (w <= 0) is marked nil (clipped) and its edges are dropped — fail-safe.
    def project(world)
      vp = M.mul(@proj, @view)
      world.entities.map do |e|
        mvp = M.mul(vp, model_matrix(e))
        pts = CUBE_VERTS.map do |vx|
          x, y, z, w = M.transform(mvp, *vx)
          next nil if w <= 1e-6
          ndc_x = x / w
          ndc_y = y / w
          sx = ((ndc_x * 0.5 + 0.5) * @w).round
          sy = ((1.0 - (ndc_y * 0.5 + 0.5)) * @h).round # flip Y for screen space
          [sx, sy]
        end
        { "id" => e["id"], "points" => pts, "edges" => CUBE_EDGES }
      end
    end
  end

  # ── SVG wireframe renderer (the visual artifact; no GPU) ───────────────────
  module Renderer
    module_function

    def screen_digest(projected)
      "sha256:#{Digest::SHA256.hexdigest(JSON.generate(projected.map { |p| p["points"] }))}"
    end

    def to_svg(projected, width: 400, height: 400)
      lines = []
      projected.each do |ent|
        pts = ent["points"]
        ent["edges"].each do |a, b|
          pa = pts[a]; pb = pts[b]
          next if pa.nil? || pb.nil? # clipped vertex -> drop edge
          lines << %(  <line x1="#{pa[0]}" y1="#{pa[1]}" x2="#{pb[0]}" y2="#{pb[1]}" stroke="#39d353" stroke-width="2"/>)
        end
      end
      <<~SVG
        <svg viewBox="0 0 #{width} #{height}" xmlns="http://www.w3.org/2000/svg">
          <rect width="#{width}" height="#{height}" fill="#0d1117"/>
        #{lines.join("\n")}
        </svg>
      SVG
    end
  end

  # A receipted frame: a deterministic projection of a world snapshot (fact/receipt-shaped).
  module Frame
    module_function

    def render(world, camera, source_receipt_id: nil)
      projected = camera.project(world)
      {
        "frame_index" => world.tick,
        "world_digest" => world.digest,
        "screen_digest" => Renderer.screen_digest(projected),
        "source_receipt_id" => source_receipt_id,
        "projected" => projected,
        "svg" => Renderer.to_svg(projected)
      }
    end
  end
end
