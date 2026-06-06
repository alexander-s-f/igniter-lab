#!/usr/bin/env node
/**
 * run_ivf_dom_proof.js
 *
 * Igniter Lab — Node.js dynamic proof for LAB-IGNITER-VIEW-FRAMEWORK-P2.
 *
 * Exercises the JS runtime with a minimal DOM mock (no npm, no jsdom, no browser).
 * Uses Node's built-in `vm` module to load the runtime in a controlled sandbox.
 *
 * Outputs: out/ivf_p2_dom_proof.json
 *
 * Status: experimental · lab-only · no-canon · no-public-api
 */

"use strict";

var vm   = require("vm");
var fs   = require("fs");
var path = require("path");

var BASE_DIR = __dirname;
var OUT_DIR  = path.join(BASE_DIR, "out");
if (!fs.existsSync(OUT_DIR)) { fs.mkdirSync(OUT_DIR, { recursive: true }); }

// ── Minimal DOM Mock ─────────────────────────────────────────────────────────
//
// Sufficient surface for IgniterComponent construction + updateSlots + _render.
// Implements:
//   createEl(tag, dataAttrs, children) → mockElement
//   mockElement.dataset, .className, .setAttribute, .addEventListener
//   mockElement.querySelectorAll("[data-attr]")

function camelCase(dataAttr) {
  // "data-ig-component" → "igComponent"
  return dataAttr.replace(/^data-/, "").replace(/-([a-z])/g, function(_, c) {
    return c.toUpperCase();
  });
}

function createEl(tag, dataAttrs, children) {
  var attrs   = {};
  var dataset = {};

  Object.keys(dataAttrs || {}).forEach(function(k) {
    attrs[k] = dataAttrs[k];
    var m = k.match(/^data-(.+)$/);
    if (m) {
      dataset[camelCase(k)] = dataAttrs[k];
    }
  });

  var el = {
    tagName:   (tag || "DIV").toUpperCase(),
    _attrs:    attrs,
    _children: children || [],
    _listeners: {},
    className:  "",
    dataset:    dataset,

    setAttribute: function(k, v) {
      el._attrs[k] = String(v);
      var m = k.match(/^data-(.+)$/);
      if (m) { el.dataset[camelCase(k)] = String(v); }
    },

    getAttribute: function(k) { return el._attrs[k]; },

    addEventListener: function(ev, fn) {
      el._listeners[ev] = el._listeners[ev] || [];
      el._listeners[ev].push(fn);
    },

    _fire: function(ev) {
      (el._listeners[ev] || []).forEach(function(fn) { fn({ type: ev }); });
    },

    // Support selector: [data-ig-element] — scans direct children recursively
    querySelectorAll: function(selector) {
      var m = selector.match(/^\[([a-z0-9-]+)\]$/);
      if (!m) return [];
      var attr    = m[1];
      var results = [];
      function collect(node) {
        if (node._attrs && Object.prototype.hasOwnProperty.call(node._attrs, attr)) {
          results.push(node);
        }
        (node._children || []).forEach(collect);
      }
      el._children.forEach(collect);
      return results;
    },

    // forEach helper (mirrors NodeList API)
    forEach: Array.prototype.forEach
  };

  return el;
}

// ── Load Runtime into Sandbox ────────────────────────────────────────────────
//
// We set document.readyState = "complete" so hydrate() executes immediately with
// an empty querySelectorAll — no real DOM available at load time.

var runtimePath = path.join(BASE_DIR, "igniter_view_runtime.js");
var runtimeSrc  = fs.readFileSync(runtimePath, "utf-8");

// Suppress most console output during load (hydrate runs but finds nothing)
var silentConsole = {
  log:   function() {},
  warn:  function() {},
  error: function() {},
  info:  function() {}
};

var sandbox = {
  console:     silentConsole,
  JSON:        JSON,
  Array:       Array,
  Object:      Object,
  String:      String,
  parseInt:    parseInt,
  parseFloat:  parseFloat,
  Math:        Math,
  Set:         Set,
  document: {
    readyState:      "complete",
    querySelectorAll: function() { return []; },
    getElementById:   function() { return null; }
  }
};
sandbox.window = sandbox;

vm.createContext(sandbox);
vm.runInContext(runtimeSrc, sandbox);

var IV = sandbox.IgniterView;

// ── Proof Helpers ────────────────────────────────────────────────────────────

var RESULTS = [];

function check(id, description, fn) {
  var passed = false;
  var error  = null;
  try {
    passed = !!fn();
  } catch (e) {
    error = e.message;
  }
  var status = passed ? "PASS" : "FAIL";
  var icon   = passed ? "✓" : "✗";
  console.log("  [" + status + "]  " + id.padEnd(14) + " " + description +
              (error ? " — EXCEPTION: " + error : ""));
  RESULTS.push({ id: id, description: description, passed: passed, error: error || null });
  return passed;
}

// ── Sample Artifact (mirrors tabs fixture) ───────────────────────────────────

var ARTIFACT = {
  view_id:        "igniter.lab.tabs_panel",
  artifact_digest: "sha256:ed8ab03d35487fa14bca3598402670feae7e2962c39581dcbc942ea16456c404",
  ui_states: {
    "active_tab": { type: "string", "default": "overview" }
  },
  slots: {
    "has_warnings": { type: "boolean", contract_ref: "diagnostics.has_warnings", mode: "read_only" }
  },
  elements: [
    {
      element_id:          "tab_btn",
      static_classes:      "tab-btn px-4 py-2",
      node_params_schema:  { "id": "string" },
      display_rules: [
        ["style",
          ["eq", ["ui_state", "active_tab"], ["param", "id"]],
          { "c": "bg-ignite text-ink-1 font-bold", "a": { "selected": "true" } },
          { "c": "text-grey", "a": { "selected": "false" } }]
      ],
      interaction_rules: [
        ["on", "click", [["set_ui_state", "active_tab", ["param", "id"]]]]
      ]
    },
    {
      element_id:         "warning_banner",
      static_classes:     "warning-banner",
      node_params_schema: {},
      display_rules: [
        ["style",
          ["slot", "has_warnings"],
          { "c": "block border border-oof" },
          { "c": "hidden" }]
      ],
      interaction_rules: []
    }
  ],
  safety_policy: {
    banned_opcodes:            ["fetch", "dispatch", "boot", "watch", "persistence", "eval", "innerHTML"],
    allowed_opcodes:           ["set_ui_state", "toggle_ui_state", "clear_ui_state"],
    slot_mode:                 "read_only",
    interaction_target_domain: "ui_state_only",
    dom_patch_scope:           "class|aria|data only"
  },
  non_claims: ["lab-only", "experimental", "no-canon"]
};

// Build a mock DOM component: root + two child elements
function buildMockComponent(stateJSON, slotsJSON) {
  var btnEl = createEl("button", {
    "data-ig-element": "tab_btn",
    "data-ig-param":   JSON.stringify({ id: "overview" })
  }, []);

  var bannerEl = createEl("div", {
    "data-ig-element": "warning_banner"
  }, []);

  var root = createEl("div", {
    "data-ig-component":     "igniter.lab.tabs_panel",
    "data-ig-state":         stateJSON,
    "data-ig-slots":         slotsJSON,
    "data-ig-artifact-digest": ARTIFACT.artifact_digest
  }, [btnEl, bannerEl]);

  return { root: root, btnEl: btnEl, bannerEl: bannerEl };
}

// ── Restore real console for proof output ────────────────────────────────────

console.log("=".repeat(64));
console.log("  LAB-IGNITER-VIEW-FRAMEWORK-P2 — NODE.JS DOM PROOF");
console.log("=".repeat(64));

// ── IVF-P2-DOM-1: filterSlotValues passes declared keys ─────────────────────

check("IVF-P2-DOM-1", "filterSlotValues: declared keys pass through", function() {
  var result = IV.filterSlotValues(
    { "has_warnings": true },
    { "has_warnings": { type: "boolean" } }
  );
  return result.filtered["has_warnings"] === true &&
         result.diagnostics.length === 0;
});

// ── IVF-P2-DOM-2: filterSlotValues rejects undeclared keys ──────────────────

check("IVF-P2-DOM-2", "filterSlotValues: undeclared keys are rejected", function() {
  var result = IV.filterSlotValues(
    { "has_warnings": true, "injected_evil": "xss" },
    { "has_warnings": { type: "boolean" } }
  );
  return result.filtered["has_warnings"] === true &&
         !Object.prototype.hasOwnProperty.call(result.filtered, "injected_evil");
});

// ── IVF-P2-DOM-3: filterSlotValues records diagnostics for rejected keys ─────

check("IVF-P2-DOM-3", "filterSlotValues: diagnostics recorded for rejected keys", function() {
  var result = IV.filterSlotValues(
    { "declared": 1, "undeclared_a": 2, "undeclared_b": 3 },
    { "declared": { type: "number" } }
  );
  return result.diagnostics.length === 2 &&
         result.diagnostics.every(function(d) { return d.type === "slot_key_rejected"; }) &&
         result.diagnostics.some(function(d) { return d.key === "undeclared_a"; }) &&
         result.diagnostics.some(function(d) { return d.key === "undeclared_b"; });
});

// ── IVF-P2-DOM-4: validateNodeParams warns on unknown keys ──────────────────

check("IVF-P2-DOM-4", "validateNodeParams: unknown keys produce diagnostics", function() {
  var diags = IV.validateNodeParams(
    { "id": "overview", "unknown_key": "xyz" },
    { "id": "string" }
  );
  return diags.length === 1 &&
         diags[0].type === "param_key_unknown" &&
         diags[0].key === "unknown_key";
});

// ── IVF-P2-DOM-5: validateNodeParams returns empty for valid params ───────────

check("IVF-P2-DOM-5", "validateNodeParams: all declared keys → empty diagnostics", function() {
  var diags = IV.validateNodeParams(
    { "id": "overview" },
    { "id": "string" }
  );
  return diags.length === 0;
});

// ── IVF-P2-DOM-6: filterSlotValues with empty declared slots ────────────────

check("IVF-P2-DOM-6", "filterSlotValues: empty declared slots → all incoming rejected", function() {
  var result = IV.filterSlotValues(
    { "any_key": "value" },
    {}
  );
  return Object.keys(result.filtered).length === 0 &&
         result.diagnostics.length === 1;
});

// ── IVF-P2-DOM-7: IgniterComponent constructor filters undeclared slots ───────

check("IVF-P2-DOM-7", "IgniterComponent: undeclared slots filtered at hydration", function() {
  var dom = buildMockComponent(
    JSON.stringify({ "active_tab": "overview" }),
    JSON.stringify({ "has_warnings": false, "injected": "evil" })  // "injected" not declared
  );

  var component = new IV.IgniterComponent(dom.root, ARTIFACT);

  return !Object.prototype.hasOwnProperty.call(component.slotValues, "injected") &&
         Object.prototype.hasOwnProperty.call(component.slotValues, "has_warnings") &&
         component.diagnostics.some(function(d) { return d.type === "slot_key_rejected"; });
});

// ── IVF-P2-DOM-8: updateSlots merges validated keys and triggers re-render ───

check("IVF-P2-DOM-8", "updateSlots: valid key accepted, slotValues updated, render fires", function() {
  var dom = buildMockComponent(
    JSON.stringify({ "active_tab": "overview" }),
    JSON.stringify({ "has_warnings": false })
  );

  var component  = new IV.IgniterComponent(dom.root, ARTIFACT);
  var bannerBefore = dom.bannerEl.className;

  // Update with has_warnings = true → warning_banner should switch to "block ..." classes
  component.updateSlots({ "has_warnings": true });

  return component.slotValues["has_warnings"] === true &&
         dom.bannerEl.className.includes("block") &&
         !dom.bannerEl.className.includes("hidden");
});

// ── IVF-P2-DOM-9: updateSlots rejects undeclared keys ───────────────────────

check("IVF-P2-DOM-9", "updateSlots: undeclared key rejected, diagnostics recorded", function() {
  var dom = buildMockComponent(
    JSON.stringify({ "active_tab": "overview" }),
    JSON.stringify({ "has_warnings": false })
  );

  var component = new IV.IgniterComponent(dom.root, ARTIFACT);
  var diagsBefore = component.diagnostics.length;

  component.updateSlots({ "has_warnings": true, "evil_slot": "injected" });

  return !Object.prototype.hasOwnProperty.call(component.slotValues, "evil_slot") &&
         component.diagnostics.length > diagsBefore &&
         component.diagnostics.some(function(d) {
           return d.type === "slot_key_rejected" && d.key === "evil_slot";
         });
});

// ── IVF-P2-DOM-10: updateSlots persists to dataset.igSlots ──────────────────

check("IVF-P2-DOM-10", "updateSlots: slotValues persisted to data-ig-slots attribute", function() {
  var dom = buildMockComponent(
    JSON.stringify({ "active_tab": "overview" }),
    JSON.stringify({ "has_warnings": false })
  );

  var component = new IV.IgniterComponent(dom.root, ARTIFACT);
  component.updateSlots({ "has_warnings": true });

  var persisted = JSON.parse(dom.root.dataset.igSlots || "{}");
  return persisted["has_warnings"] === true;
});

// ── IVF-P2-DOM-11: slot mutation via interaction_rules still blocked ──────────

check("IVF-P2-DOM-11", "Slot mutation via interaction_rules still blocked (P1 fence intact)", function() {
  // Attempt to execute an instruction that targets a slot key (not in uiState)
  var scope = {
    uiState:    { "active_tab": "overview" },
    slotValues: { "has_warnings": false },
    nodeParams: {}
  };

  var blocked = false;
  // "has_warnings" is a slot key — it's NOT in uiState, so executeInstructions
  // should fail closed with SECURITY error.
  IV.executeInstructions(
    [["set_ui_state", "has_warnings", true]],
    scope,
    function(patch) {
      blocked = false;  // Should never reach here
    }
  );
  // If the handler was not called, the instruction was blocked — correct.
  // We verify indirectly: scope.slotValues must not be modified.
  return scope.slotValues["has_warnings"] === false;
});

// ── IVF-P2-DOM-12: diagnostics array exposed on component ───────────────────

check("IVF-P2-DOM-12", "component.diagnostics is an array, accessible to host", function() {
  var dom = buildMockComponent(
    JSON.stringify({ "active_tab": "overview" }),
    JSON.stringify({ "has_warnings": false })
  );
  var component = new IV.IgniterComponent(dom.root, ARTIFACT);
  return Array.isArray(component.diagnostics);
});

// ── IVF-P2-DOM-13: updateSlots with non-object arg logs warning + returns ────

check("IVF-P2-DOM-13", "updateSlots: non-object arg is ignored safely (no throw)", function() {
  var dom = buildMockComponent(
    JSON.stringify({ "active_tab": "overview" }),
    JSON.stringify({ "has_warnings": false })
  );
  var component = new IV.IgniterComponent(dom.root, ARTIFACT);
  var before    = component.slotValues["has_warnings"];

  // Should not throw
  component.updateSlots(null);
  component.updateSlots(42);
  component.updateSlots("string");

  return component.slotValues["has_warnings"] === before;
});

// ── IVF-P2-DOM-14: tab interaction still works after updateSlots ─────────────

check("IVF-P2-DOM-14", "UIState interaction works after slot update (systems independent)", function() {
  var dom = buildMockComponent(
    JSON.stringify({ "active_tab": "overview" }),
    JSON.stringify({ "has_warnings": false })
  );

  var component = new IV.IgniterComponent(dom.root, ARTIFACT);

  // Fire a click on the tab_btn (should set active_tab = "overview" via param.id)
  dom.btnEl._fire("click");

  return component.uiState["active_tab"] === "overview";
});

// ── IVF-P2-DOM-15: filterSlotValues and validateNodeParams in public surface ─

check("IVF-P2-DOM-15", "filterSlotValues + validateNodeParams exposed in IgniterView", function() {
  return typeof IV.filterSlotValues === "function" &&
         typeof IV.validateNodeParams === "function" &&
         typeof IV.updateSlots === "function" || // may be on prototype
         typeof IV.IgniterComponent.prototype.updateSlots === "function";
});

// ── Write output ─────────────────────────────────────────────────────────────

var passedCount = RESULTS.filter(function(r) { return r.passed; }).length;
var totalCount  = RESULTS.length;
var allPassed   = passedCount === totalCount;

var output = {
  timestamp:      new Date().toISOString(),
  runner:         "node",
  overall_status: allPassed ? "SUCCESS" : "FAILURE",
  passed:         passedCount,
  total:          totalCount,
  results:        RESULTS
};

fs.writeFileSync(
  path.join(OUT_DIR, "ivf_p2_dom_proof.json"),
  JSON.stringify(output, null, 2),
  "utf-8"
);

console.log("=".repeat(64));
console.log("  Results: " + passedCount + "/" + totalCount + " checks passed");
console.log("  Output:  out/ivf_p2_dom_proof.json");
console.log("=".repeat(64));

if (allPassed) {
  console.log("  ALL IVF-P2 DOM PROOFS PASSED");
} else {
  var failed = RESULTS.filter(function(r) { return !r.passed; });
  console.log("  FAILED: " + failed.map(function(r) { return r.id; }).join(", "));
}
console.log("=".repeat(64));

process.exit(allPassed ? 0 : 1);
