/**
 * run_ivf_dom_proof_p5.js
 *
 * LAB-IGNITER-VIEW-FRAMEWORK-P5 — Node.js DOM proof for collection rendering.
 *
 * Loads igniter_view_runtime.js in a sandboxed vm context with an extended
 * mock DOM that supports cloneNode, appendChild, removeChild, and
 * [data-ig-collection] selector queries.
 *
 * No npm dependencies — stdlib only (vm, fs, crypto, path).
 *
 * Checks:
 *   P5-DOM-1:  Runtime loads without error in collection-capable context
 *   P5-DOM-2:  _renderCollection method exists on IgniterComponent prototype
 *   P5-DOM-3:  _bindElementEvents method exists on IgniterComponent prototype
 *   P5-DOM-4:  querySelectorAll("[data-ig-collection]") works in mock DOM
 *   P5-DOM-5:  cloneNode creates a separate element (not a reference)
 *   P5-DOM-6:  _renderCollection creates items from slot array
 *   P5-DOM-7:  _renderCollection applies display rules per item
 *   P5-DOM-8:  updateSlots with collection slot triggers _renderCollection
 *   P5-DOM-9:  updateSlots with non-collection slot does NOT rebuild collection
 *   P5-DOM-10: Empty items array → collection container has no item children
 *   P5-DOM-11: removeChild called to clear old items before rebuild
 *   P5-DOM-12: Undeclared slot still rejected by filterSlotValues guard
 *   P5-DOM-13: No innerHTML used in collection rendering path
 *   P5-DOM-14: component.diagnostics survives collection update with no new errors
 *   P5-DOM-15: P2 updateSlots API still works (backward compat)
 *
 * Status: experimental · lab-only · no-canon · no-public-api
 */

"use strict";

var vm   = require("vm");
var fs   = require("fs");
var path = require("path");

// ── Load runtime source ────────────────────────────────────────────────────
var RUNTIME_PATH = path.join(__dirname, "igniter_view_runtime.js");
var runtimeSrc   = fs.readFileSync(RUNTIME_PATH, "utf8");

// ── Proof helpers ──────────────────────────────────────────────────────────
var results  = [];
var failures = 0;

function check(id, label, ok, detail) {
  var status = ok ? "PASS" : "FAIL";
  results.push({ id: id, label: label, status: status, detail: detail || null });
  if (ok) {
    process.stdout.write("  ✅ " + id + ": " + label + "\n");
  } else {
    process.stderr.write("  ❌ " + id + ": " + label + (detail ? " — " + detail : "") + "\n");
    failures++;
  }
}

// ── Extended mock DOM ─────────────────────────────────────────────────────
//
// Supports:
//   - dataset (read/write via string keys)
//   - className
//   - setAttribute / getAttribute
//   - addEventListener
//   - _fire(event) for test triggering
//   - querySelectorAll with multi-attribute support: [data-a][data-b]
//   - appendChild / removeChild
//   - cloneNode(deep)
//   - parentNode reference
//   - template.content (returns self for mock; browser returns DocumentFragment)

var removedLog = [];  // track removeChild calls for P5-DOM-11

function toCamelCase(str) {
  return str.replace(/-([a-z])/g, function (_, c) { return c.toUpperCase(); });
}

function datasetKey(attrName) {
  // "data-ig-collection" → "igCollection"
  if (!attrName.startsWith("data-")) return null;
  return toCamelCase(attrName.slice(5));
}

function parseSelector(selector) {
  // Parse compound attribute selector like "[data-ig-element][data-ig-item-key]"
  var parts = [];
  var re = /\[([^\]]+)\]/g;
  var m;
  while ((m = re.exec(selector)) !== null) {
    var inner  = m[1];
    var eqIdx  = inner.indexOf("=");
    if (eqIdx === -1) {
      parts.push({ key: inner, value: null });
    } else {
      var k = inner.slice(0, eqIdx);
      var v = inner.slice(eqIdx + 1).replace(/^["']|["']$/g, "");
      parts.push({ key: k, value: v });
    }
  }
  return parts;
}

function matchesSelector(el, parts) {
  return parts.every(function (part) {
    var dsKey = datasetKey(part.key);
    if (dsKey) {
      if (part.value === null) return el.dataset[dsKey] !== undefined;
      return el.dataset[dsKey] === part.value;
    }
    return false;
  });
}

function walkEl(el, parts, acc) {
  if (!el || !el._children) return;
  el._children.forEach(function (child) {
    if (matchesSelector(child, parts)) acc.push(child);
    walkEl(child, parts, acc);
  });
}

function createEl(tag, dataAttrs) {
  var el = {
    tag:        tag,
    dataset:    {},
    _attrs:     {},
    className:  "",
    _listeners: {},
    _children:  [],
    parentNode: null,

    setAttribute: function (k, v) { this._attrs[k] = String(v); },
    getAttribute: function (k)    { return this._attrs[k] || null; },

    addEventListener: function (evt, fn) {
      if (!this._listeners[evt]) this._listeners[evt] = [];
      this._listeners[evt].push(fn);
    },
    _fire: function (evt) {
      (this._listeners[evt] || []).forEach(function (fn) { fn(); });
    },

    querySelectorAll: function (selector) {
      var parts = parseSelector(selector);
      var acc   = [];
      walkEl(this, parts, acc);
      return acc;
    },

    appendChild: function (child) {
      child.parentNode = this;
      this._children.push(child);
      return child;
    },

    removeChild: function (child) {
      var idx = this._children.indexOf(child);
      if (idx !== -1) {
        this._children.splice(idx, 1);
        child.parentNode = null;
        removedLog.push(child.dataset.igElement || child.tag);
      }
      return child;
    },

    // cloneNode: deep copy without listeners (mirror real DOM behavior)
    cloneNode: function (deep) {
      var clone = createEl(this.tag, {});
      var src   = this;
      // Copy dataset
      Object.keys(src.dataset).forEach(function (k) { clone.dataset[k] = src.dataset[k]; });
      // Copy attrs
      Object.keys(src._attrs).forEach(function (k) { clone._attrs[k] = src._attrs[k]; });
      clone.className = src.className;
      // Deep clone children (not needed for template item in P5 — template items have no children)
      if (deep) {
        src._children.forEach(function (c) {
          var cc = c.cloneNode(true);
          cc.parentNode = clone;
          clone._children.push(cc);
        });
      }
      return clone;
    }
  };

  // Set data attributes from constructor arg
  Object.keys(dataAttrs || {}).forEach(function (k) {
    var dsKey = datasetKey(k) || k;
    el.dataset[dsKey] = dataAttrs[k];
  });

  return el;
}

// Build a <template> mock that has a .content with a querySelector
function createTemplate(collectionName, elemName, itemTag) {
  var template = createEl("template", {
    "data-ig-collection-template": collectionName
  });

  // The inner item element (what gets cloned)
  var innerItem = createEl(itemTag || "li", {
    "data-ig-element": elemName
  });
  template._children.push(innerItem);

  // Provide .content as a mock DocumentFragment equivalent
  template.content = {
    querySelector: function (selector) {
      var parts = parseSelector(selector);
      if (matchesSelector(innerItem, parts)) return innerItem;
      return null;
    }
  };

  return template;
}

// ── Build a P5 test artifact ──────────────────────────────────────────────

var testArtifact = {
  view_id: "igniter.lab.results_panel",
  artifact_digest: "sha256:test-p5-digest-for-proof-only",
  ui_states: {
    sort_by: { type: "string", "default": "score" }
  },
  slots: {
    results: { type: "array",  contract_ref: "search.results", mode: "read_only" },
    query:   { type: "string", contract_ref: "search.query",   mode: "read_only" }
  },
  collections: {
    results_list: {
      slot:              "results",
      item_element:      "result_item",
      item_key:          "id",
      container_classes: "results-list flex flex-col gap-2",
      container_tag:     "ul",
      item_tag:          "li"
    }
  },
  elements: [
    {
      element_id:         "result_item",
      static_classes:     "result-item p-3 rounded-lg border list-none",
      node_params_schema: { id: "string", title: "string", status: "string", score: "integer" },
      display_rules: [
        ["match",
          ["param", "status"],
          {
            "ok":      { c: "border-ok bg-ok-5" },
            "warning": { c: "border-warn bg-warn-5" },
            "error":   { c: "border-oof bg-oof-5" }
          },
          { c: "border-line bg-ink-2" }
        ]
      ],
      interaction_rules: []
    },
    {
      element_id:         "sort_btn",
      static_classes:     "sort-btn px-3 py-1 text-xs font-mono rounded",
      node_params_schema: { target: "string" },
      display_rules: [
        ["style",
          ["eq", ["ui_state", "sort_by"], ["param", "target"]],
          { c: "bg-ignite text-ink-1 font-bold" },
          { c: "text-grey" }
        ]
      ],
      interaction_rules: [
        ["on", "click", [["set_ui_state", "sort_by", ["param", "target"]]]]
      ]
    }
  ],
  safety_policy: {
    banned_opcodes:            ["fetch", "dispatch", "boot", "watch", "persistence", "eval", "innerHTML"],
    allowed_opcodes:           ["set_ui_state", "toggle_ui_state", "clear_ui_state"],
    slot_mode:                 "read_only",
    interaction_target_domain: "ui_state_only",
    dom_patch_scope:           "class|aria|data only"
  },
  non_claims: ["lab-only", "experimental", "no-canon", "no-stable-schema"]
};

// ── Build mock DOM tree for the component ─────────────────────────────────

function buildMockRoot(initialSlots) {
  var root = createEl("div", {
    "data-ig-component":       "igniter.lab.results_panel",
    "data-ig-state":           JSON.stringify({ sort_by: "score" }),
    "data-ig-slots":           JSON.stringify(initialSlots || {}),
    "data-ig-artifact-digest": "sha256:test-p5-digest-for-proof-only"
  });

  // Collection container
  var collEl = createEl("ul", {
    "data-ig-collection":         "results_list",
    "data-ig-collection-slot":    "results",
    "data-ig-collection-element": "result_item",
    "data-ig-collection-key":     "id"
  });

  // Template element (P5) — no pre-existing items (SSR would put items here)
  var templateEl = createTemplate("results_list", "result_item", "li");
  collEl.appendChild(templateEl);

  root.appendChild(collEl);
  return root;
}

// ── Create sandbox and load runtime ───────────────────────────────────────

var mockDocument = {
  readyState: "complete",  // prevent auto-hydration
  getElementById:     function () { return null; },
  querySelectorAll:   function () { return []; },
  addEventListener:   function () {}
};

var sandbox = {
  window:   {},
  document: mockDocument,
  console:  console,
  JSON:     JSON
};
sandbox.window = sandbox;

vm.createContext(sandbox);
vm.runInContext(runtimeSrc, sandbox);

var IV = sandbox.IgniterView;

// ── Run checks ────────────────────────────────────────────────────────────

process.stdout.write("\n=== LAB-IGNITER-VIEW-FRAMEWORK-P5: Node.js DOM Proof ===\n\n");

// P5-DOM-1: Runtime loads
check("P5-DOM-1", "Runtime loads without error in collection-capable context",
      IV && typeof IV.IgniterComponent === "function");

// P5-DOM-2: _renderCollection exists
check("P5-DOM-2", "_renderCollection exists on IgniterComponent.prototype",
      typeof IV.IgniterComponent.prototype._renderCollection === "function");

// P5-DOM-3: _bindElementEvents extracted helper exists
check("P5-DOM-3", "_bindElementEvents exists on IgniterComponent.prototype",
      typeof IV.IgniterComponent.prototype._bindElementEvents === "function");

// P5-DOM-4: querySelectorAll with [data-ig-collection] in mock DOM
var testRoot4 = buildMockRoot({});
var collEls4  = testRoot4.querySelectorAll("[data-ig-collection]");
check("P5-DOM-4", "querySelectorAll('[data-ig-collection]') finds collection container",
      collEls4.length === 1 && collEls4[0].dataset.igCollection === "results_list");

// P5-DOM-5: cloneNode creates independent element
var srcEl5 = createEl("li", { "data-ig-element": "result_item" });
srcEl5.className = "original";
var clone5 = srcEl5.cloneNode(true);
clone5.className = "modified";
check("P5-DOM-5", "cloneNode creates independent element (mutation not shared)",
      srcEl5.className === "original" && clone5.className === "modified");

// P5-DOM-6: _renderCollection creates items from slot array
var root6 = buildMockRoot({});
var comp6 = new IV.IgniterComponent(root6, testArtifact);
// Initially no results
var itemsBefore = root6.querySelectorAll("[data-ig-element][data-ig-item-key]");
check("P5-DOM-6a", "Initially 0 collection items (empty slot)",
      itemsBefore.length === 0);

// Inject slot data
comp6.updateSlots({
  results: [
    { id: "r1", title: "Alpha", status: "ok",    score: 95 },
    { id: "r2", title: "Beta",  status: "error",  score: 12 },
    { id: "r3", title: "Gamma", status: "warning", score: 55 }
  ]
});

var itemsAfter = root6.querySelectorAll("[data-ig-element][data-ig-item-key]");
check("P5-DOM-6b", "_renderCollection creates 3 item elements after slot update",
      itemsAfter.length === 3);

check("P5-DOM-6c", "Items have correct data-ig-item-key values",
      itemsAfter[0] && itemsAfter[0].dataset.igItemKey === "r1" &&
      itemsAfter[1] && itemsAfter[1].dataset.igItemKey === "r2" &&
      itemsAfter[2] && itemsAfter[2].dataset.igItemKey === "r3");

// P5-DOM-7: Display rules applied per item
// r1=ok → "border-ok bg-ok-5", r2=error → "border-oof bg-oof-5"
var item7ok  = itemsAfter[0];
var item7err = itemsAfter[1];
var item7wrn = itemsAfter[2];
check("P5-DOM-7a", "ok item gets 'border-ok' class from :match display rule",
      item7ok && item7ok.className.indexOf("border-ok") !== -1);
check("P5-DOM-7b", "error item gets 'border-oof' class from :match display rule",
      item7err && item7err.className.indexOf("border-oof") !== -1);
check("P5-DOM-7c", "warning item gets 'border-warn' class from :match display rule",
      item7wrn && item7wrn.className.indexOf("border-warn") !== -1);

// P5-DOM-8: updateSlots with collection slot triggers _renderCollection
var root8 = buildMockRoot({});
var comp8 = new IV.IgniterComponent(root8, testArtifact);
comp8.updateSlots({ results: [{ id: "x1", status: "ok", title: "X1", score: 1 }] });
var items8a = root8.querySelectorAll("[data-ig-element][data-ig-item-key]");
comp8.updateSlots({ results: [
  { id: "y1", status: "error", title: "Y1", score: 2 },
  { id: "y2", status: "ok",    title: "Y2", score: 3 }
]});
var items8b = root8.querySelectorAll("[data-ig-element][data-ig-item-key]");
check("P5-DOM-8", "updateSlots replaces collection items on second call (1 → 2 items)",
      items8a.length === 1 && items8b.length === 2);

// P5-DOM-9: updateSlots with non-collection slot does NOT rebuild collection
var root9 = buildMockRoot({});
var comp9 = new IV.IgniterComponent(root9, testArtifact);
comp9.updateSlots({ results: [{ id: "z1", status: "ok", title: "Z1", score: 1 }] });
var items9Before = root9.querySelectorAll("[data-ig-element][data-ig-item-key]");
comp9.updateSlots({ query: "new search" });  // non-collection slot
var items9After  = root9.querySelectorAll("[data-ig-element][data-ig-item-key]");
check("P5-DOM-9", "Updating non-collection slot does not clear collection items",
      items9Before.length === 1 && items9After.length === 1);

// P5-DOM-10: Empty items array clears collection
var root10 = buildMockRoot({});
var comp10 = new IV.IgniterComponent(root10, testArtifact);
comp10.updateSlots({ results: [{ id: "a1", status: "ok", title: "A", score: 1 }] });
comp10.updateSlots({ results: [] });
var items10 = root10.querySelectorAll("[data-ig-element][data-ig-item-key]");
check("P5-DOM-10", "Empty items array → collection container has 0 item children",
      items10.length === 0);

// P5-DOM-11: removeChild called to clear old items
removedLog = [];
var root11 = buildMockRoot({});
var comp11 = new IV.IgniterComponent(root11, testArtifact);
comp11.updateSlots({ results: [{ id: "q1", status: "ok", title: "Q", score: 1 }] });
removedLog = [];  // reset after first build
comp11.updateSlots({ results: [{ id: "q2", status: "warning", title: "Q2", score: 2 }] });
check("P5-DOM-11", "removeChild called when rebuilding collection (q1 removed)",
      removedLog.length > 0);

// P5-DOM-12: Undeclared slot rejected (P2 guard still works)
var root12 = buildMockRoot({});
var comp12 = new IV.IgniterComponent(root12, testArtifact);
comp12.updateSlots({ results: [{ id: "k1", status: "ok", title: "K", score: 1 }],
                     __injected_evil: "payload" });
var diag12 = comp12.diagnostics.filter(function (d) { return d.type === "slot_key_rejected"; });
check("P5-DOM-12", "Undeclared slot key '__injected_evil' rejected by filterSlotValues",
      diag12.length > 0 && diag12[0].key === "__injected_evil");

// P5-DOM-13: No innerHTML in runtime (source-level check)
var noInnerHTML = !runtimeSrc.match(/\.innerHTML\s*=/);
check("P5-DOM-13", "Runtime source contains no innerHTML assignment",
      noInnerHTML);

// P5-DOM-14: Diagnostics survive collection update without spurious errors
var root14 = buildMockRoot({});
var comp14 = new IV.IgniterComponent(root14, testArtifact);
var diagBefore = comp14.diagnostics.length;
comp14.updateSlots({ results: [{ id: "m1", status: "ok", title: "M", score: 5 }] });
var diagAfter = comp14.diagnostics.length;
// No new error-type diagnostics should appear from a valid collection update
var newDiags = comp14.diagnostics.slice(diagBefore).filter(function (d) {
  return d.type !== "slot_key_rejected";  // only flag unexpected errors
});
check("P5-DOM-14", "No unexpected diagnostics added by valid collection slot update",
      newDiags.length === 0);

// P5-DOM-15: P2 backward compat — updateSlots still works for non-array slots
var root15 = buildMockRoot({});
var comp15 = new IV.IgniterComponent(root15, testArtifact);
comp15.updateSlots({ query: "hello" });
check("P5-DOM-15", "updateSlots with string slot still works (P2 backward compat)",
      comp15.slotValues.query === "hello");

// ── Write results ─────────────────────────────────────────────────────────

var OUT_DIR = require("path").join(__dirname, "out");
if (!require("fs").existsSync(OUT_DIR)) require("fs").mkdirSync(OUT_DIR, { recursive: true });

var summary = {
  runner:  "LAB-IGNITER-VIEW-FRAMEWORK-P5 (Node.js DOM)",
  total:   results.length,
  passed:  results.filter(function (r) { return r.status === "PASS"; }).length,
  failed:  results.filter(function (r) { return r.status === "FAIL"; }).length,
  results: results
};

fs.writeFileSync(
  path.join(OUT_DIR, "ivf_p5_dom_proof.json"),
  JSON.stringify(summary, null, 2)
);

process.stdout.write("\n═════════════════════════════════════════════\n");
process.stdout.write("P5 DOM Proof: " + summary.passed + "/" + summary.total + " PASS\n");

if (failures > 0) {
  process.stderr.write(failures + " check(s) FAILED\n");
  process.exit(1);
} else {
  process.stdout.write("✅ All " + summary.total + " checks PASS\n");
  process.exit(0);
}
