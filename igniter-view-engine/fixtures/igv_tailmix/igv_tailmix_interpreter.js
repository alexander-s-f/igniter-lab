#!/usr/bin/env node
'use strict';

/**
 * igv_tailmix_interpreter.js
 *
 * Proof-local minimal interpreter for Tailmix-on-Igniter definitions.
 * LAB-IGV-TAILMIX-P2 diff-oracle counterpart.
 *
 * Closed vocabulary (D8 from LAB-IGV-TAILMIX-P1):
 *   toggle / set / add_class / remove_class / toggle_class /
 *   set_attr / set_aria / show / hide / match / dispatch
 *
 * Input (first CLI argument, JSON string):
 *   { definition, state, event? }
 *   event shape: { element: string, name: string }
 *
 * Output (stdout, JSON):
 *   Success: { state, attributes, host_event? }
 *   Failure: { error: "unknown_op:<op>" }
 *
 * Fail-closed: any op not in the vocabulary returns { error } immediately.
 * No partial execution after an unknown op.
 *
 * Status: lab-only · proof-local · no-canon · no-public-api · no-stable-api
 * Authority: LAB-IGV-TAILMIX-P2 only. No implementation authority.
 */

var ALL_OPS = [
  'toggle', 'set',
  'add_class', 'remove_class', 'toggle_class',
  'set_attr', 'set_aria',
  'show', 'hide',
  'match',
  'dispatch'
];

function interpret(definition, state, event) {
  var currentState = {};
  Object.keys(state).forEach(function (k) { currentState[k] = state[k]; });

  var hostEvent = null;

  if (event) {
    var elName = event.element;
    var evName = event.name;
    var elDef = definition.elements[elName];
    if (elDef && elDef.on && elDef.on[evName]) {
      var instructions = elDef.on[evName];
      for (var i = 0; i < instructions.length; i++) {
        var inst = instructions[i];
        var op   = inst.op;

        if (ALL_OPS.indexOf(op) === -1) {
          return { error: 'unknown_op:' + op };
        }

        if (op === 'toggle') {
          var toggleKey = inst.target.replace('state.', '');
          currentState[toggleKey] = !currentState[toggleKey];
        } else if (op === 'set') {
          var setKey = inst.target.replace('state.', '');
          currentState[setKey] = inst.value;
        } else if (op === 'dispatch') {
          hostEvent = { event: inst.event, payload: inst.payload !== undefined ? inst.payload : null };
        }
        // add_class / remove_class / toggle_class / set_attr / set_aria / show / hide / match
        // are rule-level ops applied via rules[], not in event handlers in this definition model.
        // They are accepted (not unknown-op errors) but have no effect in event handler context.
      }
    }
  }

  var attributes = {};
  var elements = definition.elements;
  var elementKeys = Object.keys(elements);
  for (var ei = 0; ei < elementKeys.length; ei++) {
    var eName = elementKeys[ei];
    var eDef  = elements[eName];
    if (!eDef.rules) continue;

    for (var ri = 0; ri < eDef.rules.length; ri++) {
      var rule     = eDef.rules[ri];
      var condKey  = rule.when.replace('state.', '');
      var condVal  = currentState[condKey];
      var effect   = condVal ? rule : rule.else;
      if (!effect) continue;

      if (effect.classes) {
        var classKey = eName + '.classes';
        attributes[classKey] = (attributes[classKey] || []).concat(effect.classes);
      }
      if (effect.aria) {
        var ariaKeys = Object.keys(effect.aria);
        for (var ai = 0; ai < ariaKeys.length; ai++) {
          var ak = ariaKeys[ai];
          attributes[eName + '.aria-' + ak] = effect.aria[ak];
        }
      }
    }
  }

  var result = { state: currentState, attributes: attributes };
  if (hostEvent !== null) result.host_event = hostEvent;
  return result;
}

// ── Entry point ──────────────────────────────────────────────────────────────

var inputArg = process.argv[2];
if (!inputArg) {
  process.stderr.write('Usage: node igv_tailmix_interpreter.js \'<json>\'\n');
  process.exit(1);
}

var input;
try {
  input = JSON.parse(inputArg);
} catch (e) {
  process.stdout.write(JSON.stringify({ error: 'invalid_input_json:' + e.message }) + '\n');
  process.exit(1);
}

var result = interpret(input.definition, input.state, input.event || null);
process.stdout.write(JSON.stringify(result) + '\n');
