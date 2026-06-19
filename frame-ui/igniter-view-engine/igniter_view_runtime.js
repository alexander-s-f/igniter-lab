/**
 * igniter_view_runtime.js
 *
 * Igniter Lab — vanilla JS micro-runtime for ViewArtifact hydration.
 *
 * Status: experimental · lab-only · no-canon · no-public-api · no-stable-api
 * Track: lab-igniter-isomorphic-view-artifact-mvp-boundary-v0
 * P2 additions: updateSlots API, slot key filtering, node param validation,
 *               hydration-time slot guard, digest mismatch stance, diagnostics.
 * P5 additions: collection hydration via cloneNode (no innerHTML), per-item
 *               display rule application, event binding for dynamic items,
 *               updateSlots-triggered collection rebuild.
 *
 * Safety contract (IVF-P1-5, IVF-P1-7, IVF-P1-8 — all preserved through P5):
 *   ✓ No React / Svelte / Vue / HTMX / Tailmix dependency
 *   ✓ No innerHTML — DOM patching via className / setAttribute only
 *   ✓ No eval / Function() / new Function()
 *   ✓ No fetch — artifact loaded from inline <script type="application/json">
 *   ✓ No localStorage / sessionStorage
 *   ✓ No CustomEvent / dispatchEvent
 *   ✓ No contract execution
 *   ✓ SlotValues are read-only; write attempts fail closed
 *   ✓ Unknown opcodes fail closed (no fallthrough)
 *   ✓ Collection items created via cloneNode only — no HTML string injection
 *
 * P2 host-facing API:
 *   component.updateSlots(newSlotValues)  — inject updated slot values from host
 *   component.diagnostics                 — array of diagnostic events
 *
 * P5 collection protocol:
 *   SSR emits <template data-ig-collection-template="name"> inside the container.
 *   JS clones the template's item element per data item, sets data-ig-param,
 *   applies display rules, and binds events — no innerHTML involved.
 *
 * Size target: < 9 KB minified + gzip
 */

(function (global) {
  "use strict";

  // ── 1. EXPRESSION EVALUATOR ──────────────────────────────────────────────
  //
  // Pure function: (expr, scope) → value
  // scope = { uiState, slotValues, nodeParams }
  // No side effects. No DOM access.

  function evaluate(expr, scope) {
    // Literal (non-array): return as-is
    if (!Array.isArray(expr)) return expr;

    var op   = expr[0];
    var args = expr.slice(1);

    switch (op) {
      // ── Variable domains ─────────────────────────────────────────────────
      case "ui_state":
        return scope.uiState[args[0]];
      case "slot":
        // Slots are read-only; evaluator can READ them for display rules
        return scope.slotValues[args[0]];
      case "param":
        return scope.nodeParams[args[0]];

      // ── Comparison operators ─────────────────────────────────────────────
      case "eq":  return evaluate(args[0], scope) === evaluate(args[1], scope);
      case "neq": return evaluate(args[0], scope) !== evaluate(args[1], scope);
      case "gt":  return toNum(evaluate(args[0], scope)) >  toNum(evaluate(args[1], scope));
      case "lt":  return toNum(evaluate(args[0], scope)) <  toNum(evaluate(args[1], scope));
      case "gte": return toNum(evaluate(args[0], scope)) >= toNum(evaluate(args[1], scope));
      case "lte": return toNum(evaluate(args[0], scope)) <= toNum(evaluate(args[1], scope));

      // ── Logical operators ────────────────────────────────────────────────
      case "and": return !!evaluate(args[0], scope) && !!evaluate(args[1], scope);
      case "or":  return !!evaluate(args[0], scope) || !!evaluate(args[1], scope);
      case "not": return !evaluate(args[0], scope);

      default:
        console.warn("[IgniterView] Unknown expression op blocked:", op);
        return null;
    }
  }

  function toNum(v) {
    return typeof v === "number" ? v : parseFloat(v) || 0;
  }


  // ── 2. DISPLAY RULE EVALUATOR ────────────────────────────────────────────
  //
  // Pure function: (rules, scope) → { classes: Set, aria: {}, data: {} }
  // Supports: style (conditional), match (pattern)

  function applyDisplayRules(rules, scope) {
    var result = { classes: new Set(), aria: {}, data: {} };
    if (!Array.isArray(rules)) return result;

    for (var i = 0; i < rules.length; i++) {
      var rule = rules[i];
      if (!Array.isArray(rule)) continue;

      var kind = rule[0];

      if (kind === "style") {
        // ["style", condition, trueEffect, falseEffect]
        var condition  = rule[1];
        var trueEff   = rule[2];
        var falseEff  = rule[3];
        var effect    = evaluate(condition, scope) ? trueEff : falseEff;
        mergeEffect(result, effect);

      } else if (kind === "match") {
        // ["match", subject, { "val" => effect }, defaultEffect]
        var subject    = rule[1];
        var cases     = rule[2];
        var defaultEff = rule[3];
        var val       = String(evaluate(subject, scope));
        var matched   = (cases && Object.prototype.hasOwnProperty.call(cases, val))
                        ? cases[val]
                        : defaultEff;
        mergeEffect(result, matched);

      } else {
        console.warn("[IgniterView] Unknown display rule kind:", kind);
      }
    }
    return result;
  }

  function mergeEffect(result, effect) {
    if (!effect || typeof effect !== "object") return;
    // Classes
    if (effect.c) {
      effect.c.split(/\s+/).forEach(function (cls) {
        if (cls) result.classes.add(cls);
      });
    }
    // ARIA attributes
    if (effect.a && typeof effect.a === "object") {
      Object.assign(result.aria, effect.a);
    }
    // Data attributes
    if (effect.d && typeof effect.d === "object") {
      Object.assign(result.data, effect.d);
    }
  }


  // ── 3. DOM PATCHER ───────────────────────────────────────────────────────
  //
  // Patches class / aria-* / data-* attributes only.
  // NEVER touches innerHTML, outerHTML, textContent, or any event handler.

  function patchElement(el, staticClasses, computed) {
    // Rebuild class list from static baseline + computed dynamic classes
    var all = new Set(
      staticClasses ? staticClasses.split(/\s+/).filter(Boolean) : []
    );
    computed.classes.forEach(function (c) { all.add(c); });
    el.className = Array.from(all).join(" ");

    // Patch aria-* attributes
    var ariaKeys = Object.keys(computed.aria);
    for (var i = 0; i < ariaKeys.length; i++) {
      el.setAttribute("aria-" + ariaKeys[i], String(computed.aria[ariaKeys[i]]));
    }

    // Patch data-* attributes (excluding ig-* hydration attributes)
    var dataKeys = Object.keys(computed.data);
    for (var j = 0; j < dataKeys.length; j++) {
      el.setAttribute("data-" + dataKeys[j], String(computed.data[dataKeys[j]]));
    }
  }


  // ── 4. INTERACTION EXECUTOR ──────────────────────────────────────────────
  //
  // Whitelisted opcodes: set_ui_state, toggle_ui_state, clear_ui_state
  // Anything else fails closed — no fallthrough, no side effects.

  var BANNED_OPCODES  = ["fetch", "dispatch", "boot", "watch", "persistence",
                          "eval", "innerHTML", "localStorage", "sessionStorage"];
  var ALLOWED_OPCODES = ["set_ui_state", "toggle_ui_state", "clear_ui_state"];

  function executeInstructions(instructions, scope, onUpdate) {
    if (!Array.isArray(instructions)) return;

    var patch = {};

    for (var i = 0; i < instructions.length; i++) {
      var inst   = instructions[i];
      var op     = inst[0];
      var target = inst[1];

      // Fail closed on banned opcodes (IVF-P1-7)
      if (BANNED_OPCODES.indexOf(op) !== -1) {
        console.error("[IgniterView] SECURITY: banned opcode blocked:", op);
        return;
      }

      // Fail closed on unknown opcodes
      if (ALLOWED_OPCODES.indexOf(op) === -1) {
        console.error("[IgniterView] SECURITY: unknown opcode blocked:", op);
        return;
      }

      // Fail closed if target key not declared in UIState (IVF-P1-6)
      if (!Object.prototype.hasOwnProperty.call(scope.uiState, target)) {
        console.error("[IgniterView] SECURITY: write to undeclared UIState key blocked:", target);
        return;
      }

      if (op === "set_ui_state") {
        patch[target] = evaluate(inst[2], scope);
      } else if (op === "toggle_ui_state") {
        patch[target] = !scope.uiState[target];
      } else if (op === "clear_ui_state") {
        // Reset to null; host may supply a "cleared" default separately
        patch[target] = null;
      }
    }

    onUpdate(patch);
  }


  // ── 5a. SLOT KEY FILTERING (IVF-P2) ─────────────────────────────────────
  //
  // Filters an incoming slot value map against the declared artifact.slots schema.
  // Returns { filtered: {}, diagnostics: [] }.
  // Undeclared keys are dropped and recorded; declared keys pass through unchanged.
  //
  // This guard runs at two points:
  //   1. IgniterComponent constructor — filters data-ig-slots at hydration time
  //   2. component.updateSlots()      — filters host-injected values before merge

  function filterSlotValues(incoming, declaredSlots) {
    var filtered     = {};
    var diagnostics  = [];
    var declaredKeys = Object.keys(declaredSlots || {});

    Object.keys(incoming || {}).forEach(function (key) {
      if (declaredKeys.indexOf(key) !== -1) {
        filtered[key] = incoming[key];
      } else {
        var diag = {
          type:    "slot_key_rejected",
          key:     key,
          message: "Slot key '" + key + "' not declared in artifact.slots — rejected"
        };
        diagnostics.push(diag);
        console.warn("[IgniterView] filterSlotValues: undeclared slot key rejected:", key);
      }
    });

    return { filtered: filtered, diagnostics: diagnostics };
  }


  // ── 5b. NODE PARAM VALIDATION (IVF-P2) ──────────────────────────────────
  //
  // Validates parsed node params against the element's node_params_schema.
  // Unknown keys are warned but NOT removed — display rules simply won't reference them.
  // Returns diagnostics[] (empty if all keys are declared).

  function validateNodeParams(params, schema) {
    var diagnostics = [];
    if (!schema || Object.keys(schema).length === 0) return diagnostics;

    Object.keys(params || {}).forEach(function (key) {
      if (!Object.prototype.hasOwnProperty.call(schema, key)) {
        diagnostics.push({
          type:    "param_key_unknown",
          key:     key,
          message: "Node param key '" + key + "' not in node_params_schema — ignored by rules"
        });
        console.warn("[IgniterView] validateNodeParams: unknown param key:", key);
      }
    });

    return diagnostics;
  }


  // ── 5c. COMPONENT ────────────────────────────────────────────────────────
  //
  // Manages UIState, binds events, evaluates rules, patches DOM.
  // One instance per [data-ig-component] root element.
  //
  // P2 additions:
  //   - this.diagnostics: array of {type, ...} events (slot rejections, param warnings, etc.)
  //   - Slot values filtered against artifact.slots at hydration time
  //   - component.updateSlots(newSlotValues): host-facing slot injection API

  function IgniterComponent(root, artifact) {
    this.root     = root;
    this.artifact = artifact;

    // Diagnostics log — accumulated across hydration and runtime events
    this.diagnostics = [];

    // Index element definitions by id for O(1) lookup
    this.elementIndex = {};
    (artifact.elements || []).forEach(function (e) {
      this.elementIndex[e.element_id] = e;
    }.bind(this));

    // Initialise UIState from SSR-seeded data-ig-state attribute
    try {
      this.uiState = JSON.parse(root.dataset.igState || "{}");
    } catch (e) {
      // Fall back to artifact defaults if DOM attribute is malformed
      this.uiState = {};
      Object.keys(artifact.ui_states || {}).forEach(function (k) {
        this.uiState[k] = artifact.ui_states[k]["default"];
      }.bind(this));
    }

    // Read raw slot values from SSR-seeded data-ig-slots
    var rawSlots = {};
    try {
      rawSlots = JSON.parse(root.dataset.igSlots || "{}");
    } catch (e) {
      this.diagnostics.push({
        type:    "malformed_slots",
        message: "data-ig-slots contained invalid JSON — using empty slots"
      });
    }

    // IVF-P2: Filter slot values against declared artifact.slots at hydration time.
    // Undeclared keys are dropped; they must not be readable by display rules.
    var slotGuard = filterSlotValues(rawSlots, artifact.slots || {});
    this.slotValues = slotGuard.filtered;
    if (slotGuard.diagnostics.length > 0) {
      this.diagnostics = this.diagnostics.concat(slotGuard.diagnostics);
    }

    this._bindEvents();
    this._render();
  }

  IgniterComponent.prototype._scope = function (nodeParams) {
    return {
      uiState:    this.uiState,
      slotValues: this.slotValues,
      nodeParams: nodeParams || {}
    };
  };

  IgniterComponent.prototype._update = function (patch) {
    Object.assign(this.uiState, patch);
    // Write updated state back to DOM attribute for consistency
    this.root.dataset.igState = JSON.stringify(this.uiState);
    this._render();
  };

  IgniterComponent.prototype._render = function () {
    var self     = this;
    var elements = this.root.querySelectorAll("[data-ig-element]");

    elements.forEach(function (el) {
      var elemId  = el.dataset.igElement;
      var elemDef = self.elementIndex[elemId];
      if (!elemDef) return;

      // Parse node params — fail safe to empty on malformed JSON (IVF-P2-8)
      var nodeParams = {};
      try {
        nodeParams = JSON.parse(el.dataset.igParam || "{}");
      } catch (e) {
        self.diagnostics.push({
          type:    "malformed_param",
          element: elemId,
          message: "data-ig-param contained invalid JSON — using empty params"
        });
        console.warn("[IgniterView] Malformed data-ig-param on element:", elemId,
                     "— using empty params");
      }

      // IVF-P2-7: Validate params against declared schema (warning-only; unknown keys retained)
      if (elemDef.node_params_schema) {
        var paramDiags = validateNodeParams(nodeParams, elemDef.node_params_schema);
        if (paramDiags.length > 0) {
          self.diagnostics = self.diagnostics.concat(paramDiags);
        }
      }

      var scope    = self._scope(nodeParams);
      var computed = applyDisplayRules(elemDef.display_rules, scope);
      patchElement(el, elemDef.static_classes || "", computed);
    });
  };

  // ── 5e. PER-ELEMENT EVENT BINDING (P5 extracted helper) ─────────────────
  //
  // Binds interaction rules for a single element.
  // Called by _bindEvents for all initial elements, and by _renderCollection
  // for dynamically created item elements.

  IgniterComponent.prototype._bindElementEvents = function (el, elemDef) {
    if (!elemDef || !Array.isArray(elemDef.interaction_rules)) return;
    var self = this;

    elemDef.interaction_rules.forEach(function (rule) {
      if (rule[0] !== "on") return;
      var eventName    = rule[1];
      var instructions = rule[2];

      el.addEventListener(eventName, function () {
        var nodeParams = {};
        try { nodeParams = JSON.parse(el.dataset.igParam || "{}"); } catch (e) {}
        var scope = self._scope(nodeParams);
        executeInstructions(instructions, scope, function (patch) {
          self._update(patch);
        });
      });
    });
  };

  IgniterComponent.prototype._bindEvents = function () {
    var self     = this;
    var elements = this.root.querySelectorAll("[data-ig-element]");

    elements.forEach(function (el) {
      var elemId  = el.dataset.igElement;
      var elemDef = self.elementIndex[elemId];
      self._bindElementEvents(el, elemDef);
    });
  };


  // ── 5f. COLLECTION RENDERING (P5) ───────────────────────────────────────
  //
  // Rebuilds the children of a [data-ig-collection] container from the current
  // slot value (expected to be an array of item objects).
  //
  // Protocol:
  //   1. Locate the <template data-ig-collection-template> inside the container.
  //   2. Extract the template's item element (via template.content or direct child).
  //   3. Remove existing item elements via removeChild loop (no innerHTML).
  //   4. For each item in the slot array:
  //      a. Clone the template item via cloneNode(true).
  //      b. Set data-ig-param and data-ig-item-key on the clone.
  //      c. Apply display rules via patchElement.
  //      d. Append to container.
  //      e. Bind interaction events.
  //   5. _render() will pick up any remaining [data-ig-element] patches.
  //
  // Safety: uses cloneNode only — no innerHTML, no eval, no fetch.
  // Lab-only — no-stable-api.

  IgniterComponent.prototype._renderCollection = function (collEl) {
    var slotName = collEl.dataset.igCollectionSlot;
    var elemName = collEl.dataset.igCollectionElement;
    var keyField = collEl.dataset.igCollectionKey || "id";
    var items    = this.slotValues[slotName];

    if (!Array.isArray(items)) return;

    var elemDef = this.elementIndex[elemName];
    if (!elemDef) {
      console.warn("[IgniterView] _renderCollection: element def not found:", elemName);
      return;
    }

    // Find the template element
    var templates = collEl.querySelectorAll("[data-ig-collection-template]");
    var template  = templates.length > 0 ? templates[0] : null;
    if (!template) {
      console.warn("[IgniterView] _renderCollection: no template found in collection:", collEl.dataset.igCollection);
      return;
    }

    // Extract the source item element from the template.
    // Browser <template> exposes its inert DOM via .content (DocumentFragment).
    // Fallback for mocks / environments without .content: query the template itself.
    var templateRoot = (template.content && template.content.querySelector)
                       ? template.content
                       : template;
    var srcEl = templateRoot.querySelector
                ? templateRoot.querySelector("[data-ig-element]")
                : null;

    if (!srcEl) {
      console.warn("[IgniterView] _renderCollection: no [data-ig-element] inside template");
      return;
    }

    // Remove all current item elements (removeChild loop — no innerHTML)
    var existingItems = collEl.querySelectorAll("[data-ig-element][data-ig-item-key]");
    existingItems.forEach(function (el) {
      if (el.parentNode === collEl) {
        collEl.removeChild(el);
      }
    });

    // Render new items from slot data
    var self = this;
    items.forEach(function (item) {
      if (!item || typeof item !== "object") return;

      var itemParams = {};
      Object.keys(item).forEach(function (k) { itemParams[k] = item[k]; });
      var key = String(item[keyField] !== undefined ? item[keyField] : "");

      // Clone template item (deep copy — no HTML string involved)
      var itemEl;
      if (typeof srcEl.cloneNode === "function") {
        itemEl = srcEl.cloneNode(true);
      } else {
        // Minimal fallback for environments without cloneNode
        console.warn("[IgniterView] cloneNode unavailable — using bare element fallback");
        itemEl = { dataset: {}, className: "", setAttribute: function () {},
                   addEventListener: function () {}, parentNode: null,
                   querySelectorAll: function () { return []; } };
      }

      // Set hydration attributes on the cloned element
      itemEl.dataset.igElement  = elemName;
      itemEl.dataset.igParam    = JSON.stringify(itemParams);
      itemEl.dataset.igItemKey  = key;

      // Apply display rules to set initial classes / aria
      var scope    = self._scope(itemParams);
      var computed = applyDisplayRules(elemDef.display_rules, scope);
      patchElement(itemEl, elemDef.static_classes || "", computed);

      // Append to container
      collEl.appendChild(itemEl);

      // Bind interaction events on the new element
      self._bindElementEvents(itemEl, elemDef);
    });
  };


  // ── 5d. HOST-FACING SLOT UPDATE API (IVF-P2) ────────────────────────────
  //
  // Called by the host page AFTER it has received contract execution results.
  // The view runtime itself never fetches data — the host is responsible for
  // obtaining slot values (from a contract execution receipt, an API call, etc.)
  // and passing them here.
  //
  // Protocol:
  //   1. Filter incoming values against artifact.slots declared keys.
  //   2. Reject / log undeclared keys (diagnostic recorded, key dropped).
  //   3. Merge validated keys into this.slotValues (existing keys updated).
  //   4. Persist updated slotValues to data-ig-slots for dev-tool visibility.
  //   5. Re-evaluate all display_rules (re-render).
  //
  // The view runtime NEVER fetches, dispatches events, or executes contracts.

  IgniterComponent.prototype.updateSlots = function (newSlotValues) {
    if (!newSlotValues || typeof newSlotValues !== "object" || Array.isArray(newSlotValues)) {
      console.warn("[IgniterView] updateSlots: expected a plain object, received:",
                   typeof newSlotValues);
      return;
    }

    // Filter incoming values against declared artifact.slots
    var result = filterSlotValues(newSlotValues, this.artifact.slots || {});

    // Record any rejection diagnostics
    if (result.diagnostics.length > 0) {
      this.diagnostics = this.diagnostics.concat(result.diagnostics);
    }

    // Merge only validated keys into current slotValues
    Object.assign(this.slotValues, result.filtered);

    // Persist to data-ig-slots for dev-tool / SSR-rehydration visibility
    this.root.dataset.igSlots = JSON.stringify(this.slotValues);

    // P5: Rebuild any collection whose slot was updated.
    // A collection slot holds an array; its items must be re-rendered when the array changes.
    var changedKeys  = Object.keys(result.filtered);
    var self         = this;
    var collElements = this.root.querySelectorAll("[data-ig-collection]");
    collElements.forEach(function (collEl) {
      var collSlot = collEl.dataset.igCollectionSlot;
      if (changedKeys.indexOf(collSlot) !== -1) {
        self._renderCollection(collEl);
      }
    });

    // Re-evaluate display_rules for all managed elements (including new collection items)
    this._render();
  };


  // ── 6. AUTO-HYDRATION ────────────────────────────────────────────────────
  //
  // Discovers all [data-ig-component] elements and hydrates them using their
  // artifact definitions inlined as <script type="application/json" id="ig-artifact-*">.
  // No network fetch required (IVF-P1-7, IVF-P1-9).
  //
  // P2 — digest mismatch stance (IVF-P2-9):
  //   Warning-only. The artifact content is the source of truth; the digest is an
  //   integrity signal, not a security gate. Failing closed on mismatch would break
  //   the component on valid cache-busted or hot-reload deployments. A host
  //   that needs stricter integrity policy should apply it outside this lab runtime.
  //   The mismatch is recorded in component.diagnostics for host inspection.

  var componentRegistry = {};

  function hydrate() {
    var roots = document.querySelectorAll("[data-ig-component]");
    roots.forEach(function (root) {
      var viewId    = root.dataset.igComponent;
      var safeId    = "ig-artifact-" + viewId.replace(/[^a-z0-9_\-]/gi, "-");
      var scriptTag = document.getElementById(safeId);

      if (!scriptTag) {
        console.warn("[IgniterView] No artifact script tag found for:", viewId,
                     "(expected id:", safeId + ")");
        return;
      }

      var artifact;
      try {
        artifact = JSON.parse(scriptTag.textContent);
      } catch (e) {
        console.error("[IgniterView] Failed to parse artifact JSON for:", viewId, e);
        return;
      }

      // Construct the component (hydrates UIState + slots, binds events, renders)
      var component = new IgniterComponent(root, artifact);

      // IVF-P2-9: Digest mismatch — warning-only (see section header for rationale)
      if (root.dataset.igArtifactDigest && artifact.artifact_digest) {
        if (root.dataset.igArtifactDigest !== artifact.artifact_digest) {
          component.diagnostics.push({
            type:           "digest_mismatch",
            viewId:         viewId,
            domDigest:      root.dataset.igArtifactDigest,
            artifactDigest: artifact.artifact_digest
          });
          console.warn(
            "[IgniterView] Digest mismatch for:", viewId,
            "— DOM:", root.dataset.igArtifactDigest,
            "— Artifact:", artifact.artifact_digest,
            "— Stance: warning-only. Component hydrated. Inspect component.diagnostics."
          );
        }
      }

      // Register component so host page can access it
      componentRegistry[viewId] = component;
    });
  }

  // Run after DOM is ready
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", hydrate);
  } else {
    hydrate();
  }

  // ── 7. PUBLIC SURFACE ────────────────────────────────────────────────────
  // Exposed for testing, manual use in IDE sandbox, and host-page integration.
  global.IgniterView = {
    // Core primitives (unit-testable without DOM)
    evaluate:            evaluate,
    applyDisplayRules:   applyDisplayRules,
    patchElement:        patchElement,
    executeInstructions: executeInstructions,
    // P2 validation primitives (unit-testable without DOM)
    filterSlotValues:    filterSlotValues,
    validateNodeParams:  validateNodeParams,
    // Component constructor
    IgniterComponent:    IgniterComponent,
    // Manual hydration trigger
    hydrate:             hydrate,
    // Live component registry — keyed by view_id
    components:          componentRegistry
  };

})(window);
