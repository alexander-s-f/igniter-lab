# Feasibility Study: Native Graphic GUI System on Igniter Lang

Status: `experimental · lab-only · research`
Track: `lab-igniter-lang-native-graphics-gui-feasibility-study-v0`
Base: `Language Covenant (Postulates 2, 4, 5, 6, 8, 27, 28)`, `lab-igniter-lang-to-gui-research-boundary-v0.md`
Author: `[Igniter-Lang Research Agent]`
Date: 2026-06-06

---

## 1. Executive Summary

This study investigates the **conceptual feasibility and architectural design** of a native cross-platform GUI system for the **Igniter Language** that completely bypasses HTML, Webviews (Tauri), and JavaScript runtimes.

Instead of translating view declarations into web elements, this model compiles layouts into a platform-agnostic **Vector Scene Graph AST** rendered directly on the GPU (via Metal, Vulkan, DX12, or WebGL) using modern Rust graphics pipelines (such as `WGPU` or `Vello`).

### High-Level Verdict: Exceptionally Feasible & Aligned
We conclude that a native graphics approach is **conceptually superior** to the HTML/Webview model. It offers complete escape from the legacy baggage of the DOM, enables microsecond-level render latency, and allows us to represent **UI layouts directly as Igniter dependency graphs**. This means layout calculation (size, padding, positioning) gets compiled-time cyclic verification and runtime cache-invalidation *for free* via the Igniter Compiler and VM.

---

## 2. Native Graphics Architecture vs. HTML/Webview

To understand the shift, we compare the two paradigms across core GUI elements:

| Component | Webview/HTML Model (Tauri) | Native Graphic System (Vello/WGPU) |
| :--- | :--- | :--- |
| **Presentation AST** | HTML tag whitelist (`div`, `span`, `p`) | Drawing primitives (`Rect`, `Text`, `Path`, `Group`) |
| **Layout Engine** | Browser engine (Blink/Webkit flexbox & grid) | Rust-native layout engine (`Taffy` or VM DAG nodes) |
| **Render Output** | DOM serialization + browser painting | GPU render pipeline (vector path rasterization) |
| **Event Loop** | Browser events (`click`, `keydown`) bubbled | OS events (`winit`) resolved via quad-tree hit-testing |
| **Runtime Language** | Vanilla Javascript (`igniter_view_runtime.js`) | Compiled Rust/Swift/Kotlin native window shell |
| **Security Gates** | CSP header sandboxing + Javascript blocking | Physical memory safety + Rust Capability Passports |

---

## 3. Core Concept: Layout as a Dependency DAG

One of the most powerful aspects of a native graphics GUI on Igniter Lang is the ability to compile the layout tree directly into an **Igniter Dependency Graph**.

In traditional UI frameworks, layout is calculated via dynamic constraint solvers or recursive tree passes (like Flutter's `layout()` or CSS reflows), which are prone to cyclic dependency locks and performance hiccups.

In Igniter, we model layout nodes as pure **Compute Nodes** inside the contract DAG:

```
             ┌──────────────────────────────────────────────┐
             │         window_width (Input Port)            │
             └──────┬────────────────────────────────┬──────┘
                    │                                │
                    ▼                                ▼
       ┌────────────────────────┐        ┌────────────────────────┐
       │   sidebar_width        │        │   content_width        │
       │   (Compute Node)       │        │   (Compute Node)       │
       │   Value: 240px         │        │   Formula:             │
       │                        │        │   window_width -       │
       │                        │        │   sidebar_width        │
       └────────────────────────┘        └───────────┬────────────┘
                                                     │
                                                     ▼
                                         ┌────────────────────────┐
                                         │   grid_cols_count      │
                                         │   (Compute Node)       │
                                         │   Formula:             │
                                         │   content_width / 300px│
                                         └────────────────────────┘
```

### Advantages of DAG Layout
1. **Compile-Time Cyclic Verification**: The Igniter compiler (`GraphCompiler`) validates the layout tree. If a parent's size depends on a child and the child's size simultaneously depends on the parent in a circular loop, the compiler flags it as a compile-time layout error.
2. **Granular Cache Invalidation**: When a user resizes a window, only the layout nodes dependent on `window_width` are marked dirty. Elements inside static containers (e.g. sidebar links) are not re-calculated, achieving optimal execution performance.
3. **Bitemporal UI Time-Travel**: Because the layout is a pure computation graph driven by bitemporal inputs, we can replay the visual state of the GUI at any point in history. We can audit exactly how a layout error or overflow occurred by stepping back in transaction-time.

---

## 4. The Render Pipeline: GPU-Accelerated Vector Graphics

Instead of drawing pixels onto a bitmap via CPU buffers, the native system leverages a modern GPU-accelerated vector rendering engine.

```
┌──────────────────┐
│   .igg Source    │  (Native Graphics DSL)
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│   ViewArtifact   │  (Vector Scene AST: Rect, RoundedRect, Text, Path)
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Layout Resolver │  (Taffy / VM Layout DAG calculates bounding boxes)
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Vello / WGPU    │  (Vulkan/Metal/DX12 GPU pipeline)
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Screen Buffer   │  (Sub-millisecond frame rendering)
└──────────────────┘
```

### 4.1 Graphics DSL (`.igg`)
Layouts are authored in a graphics-centric View DSL:

```ruby
graphic_view "igniter.lab.dashboard_scene" do
  state :zoom_level, type: "decimal", default: 1.0

  slot :nodes_data, type: "array", from: "compiler.dag_nodes"

  # Container with explicit vector coordinate space
  canvas :main_viewport, width: 800, height: 600 do
    # Background rectangle
    rect x: 0, y: 0, w: %parent.w, h: %parent.h, fill: "#15110d"

    # Repeated vector components
    layer :nodes_group do
      collection :dag_elements, slot: :nodes_data, item_element: :node_sprite, item_key: :id
    end
  end

  element :node_sprite do
    param :id, type: "string"
    param :x, type: "decimal"
    param :y, type: "decimal"
    param :label, type: "string"
    param :class, type: "string"

    # Dynamic styling maps directly to drawing command changes
    display :style,
            condition: eq(%active_node_id, param(:id)),
            on_true:  { stroke: "#ff6a3d", stroke_width: 2.0 },
            on_false: { stroke: "#9a8a7c", stroke_width: 1.0 }

    # Draw rounded rect & text
    rounded_rect x: param(:x), y: param(:y), w: 120, h: 40, rx: 8, ry: 8, fill: "#221b15"
    text x: param(:x) + 10, y: param(:y) + 24, content: param(:label), font: "monospace", size: 12, fill: "#e7ddd2"

    on :click, set_ui_state(:active_node_id, param(:id))
  end
end
```

### 4.2 Drawing Pipeline
1. **Scene Generation**: The compiler lowers the `.igg` file into a JSON AST of drawing commands.
2. **Layout Phase**: Bounding boxes are calculated for all primitives based on their constraints (using a Rust layout engine like `Taffy` or VM computation nodes).
3. **Encoding Phase**: The drawing primitives (shapes, strokes, fills, text paths) are translated into vector command streams.
4. **GPU Rasterization**: We feed the command streams into a compute-shader-based renderer (like **Vello** or **Piet-GPU**). The GPU handles anti-aliasing and rasterizes curves, shapes, and fonts in a few microseconds, bypassing CPU memory bottlenecks.

---

## 5. Input Handling & Event Routing

Since we have no browser to capture clicks, the native host (e.g. built in Rust using `winit` or `sdl2`) handles raw hardware inputs.

### 5.1 Quad-Tree Hit-Testing
To route a mouse click event:
1. **Event Capture**: The OS windowing shell emits a `CursorPressed { x, y }` event.
2. **Space Transformation**: The coordinates are transformed based on the camera scale and pan offsets of the viewport.
3. **Spatial Query**: The renderer queries a spatial database (e.g., a **Quad-Tree** or **R-Tree** containing the computed bounding boxes of all interactive elements).
4. **Hit Resolution**: It identifies the top-most active element containing the coordinates (e.g., `node_sprite` with parameter `id: "compute_a"`).
5. **Action Dispatch**: The event dispatcher reads the element's interaction rules and maps them to VM commands.

---

## 6. Covenant Compliance & Security Gaps

Shifting to a native graphics architecture resolves several safety concerns and creates a highly secure environment aligned with the **Language Covenant**:

### 6.1 Capability Isolation for Native Assets
* **The Webview Risk**: An HTML view can import external images via `<img src="http://attacker.com/leak.png">` to leak user data (telemetry leaks).
* **Native Graphic Mitigation**: The rendering pipeline has no networking stack. Image resources must be fetched via an explicit FFI asset loader. This loader requires a **Capability Passport** verifying that the view has authorization to access the specific asset directory or URL.

### 6.2 Deterministic UI Auditing
Under Postulate 27 (Accountability), the UI should not exhibit random, untraceable behaviors.
* In this native system, the UI frame state is completely defined by two immutable values: `UIState` + `SlotValues`.
* We can record the entire user session as a sequence of input events. Replaying this sequence against the compiled `.igapp` and scene graph reproduces the exact pixel-by-pixel rendering, enabling complete visual auditability.

---

## 7. Conceptual Proof of Concept (POC) in Rust

To prove this system, we can design a Rust-native runner inside `/igniter-lab/igniter-gui-engine`.

```
igniter-gui-engine/
  ├── Cargo.toml
  └── src/
      ├── main.rs         # Entry point: runs event loop & WGPU/Vello window
      ├── scene.rs        # Parsed Vector Scene Graph AST
      ├── layout.rs       # Integrates Taffy layout engine
      ├── renderer.rs     # Encodes primitives into Vello GPU encoders
      └── input.rs        # Quad-tree hit-testing and event dispatcher
```

### Proposed Dependency Stack
* **`winit`**: OS window creation and event loop monitoring.
* **`vello`**: Compute-shader GPU vector drawing (supports SVG-like paths, fills, strokes, and gradients).
* **`taffy`**: Rust implementation of Flexbox and Grid layout specifications.
* **`parry2d`**: Spatial partition structures for sub-microsecond hit-testing.
* **`igniter-machine`**: Fuses the VM and TBackend into the GUI process for local data dispatch.

---

## 8. Open Questions & Roadmap

Implementing a native GPU-accelerated graphic GUI requires addressing several research frontiers:

### 8.1 Font Rasterization & Internationalization
* **Question**: Font rendering is notoriously difficult to implement natively across platforms (handling emoji, right-to-left languages, and subpixel positioning).
* **Options**:
  1. *Subprocess fallback*: Rely on OS-native text rasterization (e.g. CoreText on macOS, DirectWrite on Windows) and upload glyphs to the GPU texture atlas.
  2. *Integrated shaping*: Use standard libraries like `harfbuzz` and `swash` to compile paths for all glyphs directly inside the Vello pipeline.

### 8.2 Component Composition & Drawing Layers
* **Question**: How do we handle custom layout clipping and overlapping layers (like modal overlays or context menus) without HTML's `z-index` and overflow styling?
* **Proposal**: Introduce rendering layers with clipping path parameters in the scene graph. The renderer evaluates the tree, splits drawings into separate command encoders, and composites them on the GPU.

---

## 9. Next Steps and Recommendations

We recommend a progressive, phased approach to prove this architecture:

1. **Phase 1: Scene Graph Definition**:
   Define the JSON schema for `scene_tree.json` including standard graphic primitives (Rect, Circle, Path, Text, Group) and layout parameters.
2. **Phase 2: Rust Headless Layout Proof**:
   Write a headless Rust script that loads a `scene_tree.json`, feeds layout constraints to `Taffy`, and outputs calculated bounding boxes, validating the layout resolver without launching a GPU window.
3. **Phase 3: Vello Renderer Integration**:
   Build a minimal Rust window application using `winit` and `vello` that loads the layout outputs and rasterizes the shapes on the screen, creating a static vector layout demo.
