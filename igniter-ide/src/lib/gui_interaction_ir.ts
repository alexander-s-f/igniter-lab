// igniter-lab/igniter-ide/src/lib/gui_interaction_ir.ts

/**
 * ��� Igniter Lang - GUI Interaction IR (Lab-Only Prototype)
 * Inspired by Tailmix concepts but strictly bounded to Igniter's safety covenants.
 *
 * Safety Boundaries:
 * - UIState (transient, local UI flags) and SlotValue (immutable contract outputs) are separated.
 * - SlotValue is read-only and CANNOT be targeted by any mutation.
 * - Display rules are pure and read-only.
 * - Interaction rules can only mutate UIState via whitelisted opcodes.
 * - Direct HTTP (fetch), event bubbling (dispatch), lifecycle (boot), reactive observers (watch),
 *   and persistence are explicitly rejected.
 */

// ������ 1. SCHEMA DEFINITIONS ������������������������������������������������������������������������������������������������������������������������������������������������������������

export type UIState = Record<string, any>;
export type SlotValue = any;
export type SlotValues = Record<string, SlotValue>;
export type NodeParams = Record<string, any>;

export interface AttributeEffect {
  c?: string;                 // CSS Classes
  a?: Record<string, any>;    // ARIA Attributes
  d?: Record<string, any>;    // Data Attributes
  p?: Record<string, any>;    // Custom Properties
}

// LISP-like expression arrays
export type Expression =
  | any // Literal values (string, number, boolean, null)
  | ['ui_state', string]
  | ['slot', string]
  | ['param', string]
  | ['eq', Expression, Expression]
  | ['neq', Expression, Expression]
  | ['gt', Expression, Expression]
  | ['lt', Expression, Expression]
  | ['gte', Expression, Expression]
  | ['lte', Expression, Expression]
  | ['and', Expression, Expression]
  | ['or', Expression, Expression]
  | ['not', Expression];

export type DisplayRule =
  | ['style', Expression, AttributeEffect, AttributeEffect | null]
  | ['match', Expression, Record<string, AttributeEffect>, AttributeEffect | null];

export type WhitelistedOpcode = 'set_ui_state' | 'toggle_ui_state' | 'clear_ui_state';

export type Instruction =
  | ['set_ui_state', string, Expression]
  | ['toggle_ui_state', string]
  | ['clear_ui_state', string];

export type InteractionRule = ['on', string, Instruction[]];

export interface DiagnosticInfo {
  rule?: string;
  message: string;
  severity: 'error' | 'warning' | 'info';
}

export interface DisplayEvaluationResult {
  success: boolean;
  effect: AttributeEffect | null;
  diagnostics: DiagnosticInfo[];
}

export interface InteractionEvaluationResult {
  success: boolean;
  mutatedUiState: UIState | null;
  diagnostics: DiagnosticInfo[];
}

// ������ 2. PURE EXPRESSION EVALUATOR ���������������������������������������������������������������������������������������������������������������������������������������

export function evaluateExpression(
  expr: Expression,
  uiState: UIState,
  slotValues: SlotValues,
  nodeParams: NodeParams
): { success: boolean; value: any; diagnostics: DiagnosticInfo[] } {
  const diagnostics: DiagnosticInfo[] = [];

  // 1. Literal values (primitive non-arrays)
  if (!Array.isArray(expr)) {
    return { success: true, value: expr, diagnostics };
  }

  const op = expr[0];
  const args = expr.slice(1);

  try {
    switch (op) {
      // Banned access domains
      case 'event':
        // Event is strictly isolated to interaction rules, not display rules
        diagnostics.push({
          message: `Expression Error: Banned domain reference 'event' in display expression`,
          severity: 'error'
        });
        return { success: false, value: null, diagnostics };

      // Variable scopes
      case 'ui_state': {
        const key = args[0] as string;
        if (!(key in uiState)) {
          diagnostics.push({
            message: `Evaluation warning: UIState key '${key}' is undefined`,
            severity: 'warning'
          });
        }
        return { success: true, value: uiState[key], diagnostics };
      }

      case 'slot': {
        const key = args[0] as string;
        if (!(key in slotValues)) {
          diagnostics.push({
            message: `Evaluation warning: Slot reference '${key}' is undefined`,
            severity: 'warning'
          });
        }
        return { success: true, value: slotValues[key], diagnostics };
      }

      case 'param': {
        const key = args[0] as string;
        if (!(key in nodeParams)) {
          diagnostics.push({
            message: `Evaluation warning: Parameter key '${key}' is undefined`,
            severity: 'warning'
          });
        }
        return { success: true, value: nodeParams[key], diagnostics };
      }

      // Operators
      case 'eq': {
        const left = evaluateExpression(args[0], uiState, slotValues, nodeParams);
        const right = evaluateExpression(args[1], uiState, slotValues, nodeParams);
        diagnostics.push(...left.diagnostics, ...right.diagnostics);
        if (!left.success || !right.success) return { success: false, value: null, diagnostics };
        return { success: true, value: left.value === right.value, diagnostics };
      }

      case 'neq': {
        const left = evaluateExpression(args[0], uiState, slotValues, nodeParams);
        const right = evaluateExpression(args[1], uiState, slotValues, nodeParams);
        diagnostics.push(...left.diagnostics, ...right.diagnostics);
        if (!left.success || !right.success) return { success: false, value: null, diagnostics };
        return { success: true, value: left.value !== right.value, diagnostics };
      }

      case 'gt': {
        const left = evaluateExpression(args[0], uiState, slotValues, nodeParams);
        const right = evaluateExpression(args[1], uiState, slotValues, nodeParams);
        diagnostics.push(...left.diagnostics, ...right.diagnostics);
        if (!left.success || !right.success) return { success: false, value: null, diagnostics };
        return { success: true, value: left.value > right.value, diagnostics };
      }

      case 'lt': {
        const left = evaluateExpression(args[0], uiState, slotValues, nodeParams);
        const right = evaluateExpression(args[1], uiState, slotValues, nodeParams);
        diagnostics.push(...left.diagnostics, ...right.diagnostics);
        if (!left.success || !right.success) return { success: false, value: null, diagnostics };
        return { success: true, value: left.value < right.value, diagnostics };
      }

      case 'gte': {
        const left = evaluateExpression(args[0], uiState, slotValues, nodeParams);
        const right = evaluateExpression(args[1], uiState, slotValues, nodeParams);
        diagnostics.push(...left.diagnostics, ...right.diagnostics);
        if (!left.success || !right.success) return { success: false, value: null, diagnostics };
        return { success: true, value: left.value >= right.value, diagnostics };
      }

      case 'lte': {
        const left = evaluateExpression(args[0], uiState, slotValues, nodeParams);
        const right = evaluateExpression(args[1], uiState, slotValues, nodeParams);
        diagnostics.push(...left.diagnostics, ...right.diagnostics);
        if (!left.success || !right.success) return { success: false, value: null, diagnostics };
        return { success: true, value: left.value <= right.value, diagnostics };
      }

      case 'and': {
        const left = evaluateExpression(args[0], uiState, slotValues, nodeParams);
        if (!left.success) return { success: false, value: null, diagnostics: [...diagnostics, ...left.diagnostics] };
        if (!left.value) return { success: true, value: false, diagnostics: [...diagnostics, ...left.diagnostics] };
        const right = evaluateExpression(args[1], uiState, slotValues, nodeParams);
        return { success: true, value: !!right.value, diagnostics: [...diagnostics, ...left.diagnostics, ...right.diagnostics] };
      }

      case 'or': {
        const left = evaluateExpression(args[0], uiState, slotValues, nodeParams);
        if (!left.success) return { success: false, value: null, diagnostics: [...diagnostics, ...left.diagnostics] };
        if (left.value) return { success: true, value: true, diagnostics: [...diagnostics, ...left.diagnostics] };
        const right = evaluateExpression(args[1], uiState, slotValues, nodeParams);
        return { success: true, value: !!right.value, diagnostics: [...diagnostics, ...left.diagnostics, ...right.diagnostics] };
      }

      case 'not': {
        const child = evaluateExpression(args[0], uiState, slotValues, nodeParams);
        diagnostics.push(...child.diagnostics);
        if (!child.success) return { success: false, value: null, diagnostics };
        return { success: true, value: !child.value, diagnostics };
      }

      default:
        diagnostics.push({
          message: `Expression Error: Unknown/Unsafe operator or function call '${op}' in display expression`,
          severity: 'error'
        });
        return { success: false, value: null, diagnostics };
    }
  } catch (err: any) {
    diagnostics.push({
      message: `Expression Crash: Exception occurred while evaluating '${op}': ${err?.message || err}`,
      severity: 'error'
    });
    return { success: false, value: null, diagnostics };
  }
}

// ������ 3. PURE DISPLAY RULES EVALUATOR ������������������������������������������������������������������������������������������������������������������������������

export function evaluateDisplayRule(
  rule: DisplayRule,
  uiState: UIState,
  slotValues: SlotValues,
  nodeParams: NodeParams
): DisplayEvaluationResult {
  const diagnostics: DiagnosticInfo[] = [];

  if (!Array.isArray(rule)) {
    diagnostics.push({ message: "Malformed display rule: not an array", severity: "error" });
    return { success: false, effect: null, diagnostics };
  }

  const kind = rule[0];

  if (kind === 'style') {
    const [_, condition, consequent, alternate] = rule;
    const condRes = evaluateExpression(condition, uiState, slotValues, nodeParams);
    diagnostics.push(...condRes.diagnostics);

    if (!condRes.success) {
      return { success: false, effect: null, diagnostics };
    }

    if (condRes.value) {
      return { success: true, effect: consequent, diagnostics };
    } else {
      return { success: true, effect: alternate || null, diagnostics };
    }
  }

  if (kind === 'match') {
    const [_, subject, cases, defaultCase] = rule;
    const subRes = evaluateExpression(subject, uiState, slotValues, nodeParams);
    diagnostics.push(...subRes.diagnostics);

    if (!subRes.success) {
      return { success: false, effect: null, diagnostics };
    }

    const key = String(subRes.value);
    if (cases && key in cases) {
      return { success: true, effect: cases[key], diagnostics };
    } else {
      return { success: true, effect: defaultCase || null, diagnostics };
    }
  }

  diagnostics.push({
    message: `Malformed display rule: Unknown rule kind '${kind}'`,
    severity: 'error'
  });
  return { success: false, effect: null, diagnostics };
}

// ������ 4. SAFE INTERACTION RULES EVALUATOR ������������������������������������������������������������������������������������������������������������������

export function evaluateInteractionRule(
  rule: InteractionRule,
  localEventValue: any, // local event payload (e.g. key/value for click parameters)
  uiState: UIState,
  slotValues: SlotValues,
  nodeParams: NodeParams
): InteractionEvaluationResult {
  const diagnostics: DiagnosticInfo[] = [];

  if (!Array.isArray(rule) || rule[0] !== 'on') {
    diagnostics.push({ message: "Malformed interaction rule: missing 'on' trigger", severity: "error" });
    return { success: false, mutatedUiState: null, diagnostics };
  }

  const [_, eventName, instructions] = rule;
  const newUiState = { ...uiState };

  if (!Array.isArray(instructions)) {
    diagnostics.push({ message: "Malformed interaction instructions: not an array", severity: "error" });
    return { success: false, mutatedUiState: null, diagnostics };
  }

  for (const inst of instructions) {
    if (!Array.isArray(inst)) {
      diagnostics.push({ message: "Malformed instruction payload", severity: "error" });
      return { success: false, mutatedUiState: null, diagnostics };
    }

    const op = inst[0];
    const args = inst.slice(1);

    // Reject Tailmix side-effect opcodes
    if (['fetch', 'dispatch', 'boot', 'watch', 'persistence'].includes(op)) {
      diagnostics.push({
        message: `Interaction Security Violation: Banned side-effect opcode '${op}' is blocked by Covenant Passport`,
        severity: 'error'
      });
      return { success: false, mutatedUiState: null, diagnostics };
    }

    if (op === 'set_ui_state') {
      const target = args[0] as string;
      const expr = args[1];

      // Block writing to anything except declared UIState keys
      if (!(target in uiState)) {
        diagnostics.push({
          message: `Interaction Error: Target UIState key '${target}' does not exist. Mutation blocked.`,
          severity: 'error'
        });
        return { success: false, mutatedUiState: null, diagnostics };
      }

      // Evalluate the expression
      const exprRes = evaluateExpression(expr, newUiState, slotValues, { ...nodeParams, event: localEventValue });
      diagnostics.push(...exprRes.diagnostics);

      if (!exprRes.success) {
        return { success: false, mutatedUiState: null, diagnostics };
      }

      newUiState[target] = exprRes.value;
    }
    else if (op === 'toggle_ui_state') {
      const target = args[0] as string;

      if (!(target in uiState)) {
        diagnostics.push({
          message: `Interaction Error: Target UIState key '${target}' does not exist. Toggle blocked.`,
          severity: 'error'
        });
        return { success: false, mutatedUiState: null, diagnostics };
      }

      newUiState[target] = !newUiState[target];
    }
    else if (op === 'clear_ui_state') {
      const target = args[0] as string;

      if (!(target in uiState)) {
        diagnostics.push({
          message: `Interaction Error: Target UIState key '${target}' does not exist. Clear blocked.`,
          severity: 'error'
        });
        return { success: false, mutatedUiState: null, diagnostics };
      }

      // Hard-coded default for clear operation
      newUiState[target] = null;
    }
    else {
      // Handle Tailmix opcode 'set' or 'toggle' targeted improperly
      diagnostics.push({
        message: `Interaction Security Violation: Unknown or unwhitelisted opcode '${op}'. Only set_ui_state, toggle_ui_state, and clear_ui_state are whitelisted.`,
        severity: 'error'
      });
      return { success: false, mutatedUiState: null, diagnostics };
    }
  }

  return { success: true, mutatedUiState: newUiState, diagnostics };
}

// ������ 5. PROOF FIXTURES & DETERMINISTIC TRANSITIONS ������������������������������������������������������������������������������������

export const PROOF_FIXTURES = {
  // Pilot case: Tab navigation component
  tabs: {
    uiState: {
      active_tab: 'overview'
    },
    slotValues: {
      is_locked: false
    },
    nodeParams: {
      id: 'profile'
    },
    displayRules: [
      // If active_tab === param.id, highlight border and set ARIA selected
      [
        'style',
        ['eq', ['ui_state', 'active_tab'], ['param', 'id']],
        { c: 'border-b-2 border-ignite text-ignite', a: { selected: true } },
        { c: 'border-transparent text-grey hover:text-warm-3', a: { selected: false } }
      ]
    ] as DisplayRule[],
    interactionRules: [
      // On click, set active_tab to param.id (i.e. 'profile')
      [
        'on',
        'click',
        [
          ['set_ui_state', 'active_tab', ['param', 'id']]
        ]
      ]
    ] as InteractionRule[]
  },

  // Pilot case: Expandable details accordion panel
  panel: {
    uiState: {
      is_expanded: false
    },
    slotValues: {
      has_errors: true
    },
    nodeParams: {},
    displayRules: [
      // Toggle CSS block vs hidden based on UIState
      [
        'style',
        ['ui_state', 'is_expanded'],
        { c: 'block mt-2' },
        { c: 'hidden' }
      ],
      // Apply error indicator border if contract outputs error (from SlotValue)
      [
        'style',
        ['slot', 'has_errors'],
        { c: 'border border-oof bg-oof/5' },
        null
      ]
    ] as DisplayRule[],
    interactionRules: [
      // On toggle, flip is_expanded boolean
      [
        'on',
        'click',
        [
          ['toggle_ui_state', 'is_expanded']
        ]
      ]
    ] as InteractionRule[]
  }
};

/**
 * Deterministic test runner to execute proofs in unit check contexts.
 * Returns confirmation matrices.
 */
export function runVerificationProofs(): { success: boolean; log: string[] } {
  const log: string[] = [];
  let success = true;

  log.push("��� Starting Igniter GUI IR Verification Proofs...");

  // 1. Tab Navigation Verification
  const tabFix = PROOF_FIXTURES.tabs;
  log.push(`[Tab Proof] Initial state: active_tab = '${tabFix.uiState.active_tab}'`);

  // Test Display Evaluation in initial state ('overview' != 'profile')
  const initialDisp = evaluateDisplayRule(tabFix.displayRules[0], tabFix.uiState, tabFix.slotValues, tabFix.nodeParams);
  log.push(`[Tab Proof] Initial display classes: '${initialDisp.effect?.c}' (selected = ${initialDisp.effect?.a?.selected})`);
  if (initialDisp.effect?.a?.selected !== false) {
    log.push("��� Tab Proof Error: Initial display should be inactive");
    success = false;
  }

  // Test Interaction: click on the 'profile' tab
  const clickRule = tabFix.interactionRules[0];
  const clickRes = evaluateInteractionRule(clickRule, {}, tabFix.uiState, tabFix.slotValues, tabFix.nodeParams);
  if (!clickRes.success || !clickRes.mutatedUiState) {
    log.push(`��� Tab Proof Error: Interaction click failed: ${JSON.stringify(clickRes.diagnostics)}`);
    success = false;
  } else {
    const mutatedState = clickRes.mutatedUiState;
    log.push(`[Tab Proof] Mutated state: active_tab = '${mutatedState.active_tab}'`);
    if (mutatedState.active_tab !== 'profile') {
      log.push("��� Tab Proof Error: active_tab was not set to 'profile'");
      success = false;
    }

    // Re-evaluate display in mutated state
    const postDisp = evaluateDisplayRule(tabFix.displayRules[0], mutatedState, tabFix.slotValues, tabFix.nodeParams);
    log.push(`[Tab Proof] Post-click display classes: '${postDisp.effect?.c}' (selected = ${postDisp.effect?.a?.selected})`);
    if (postDisp.effect?.a?.selected !== true) {
      log.push("��� Tab Proof Error: Display did not highlight after transition");
      success = false;
    }
  }

  // 2. Expandable Panel Verification
  const panelFix = PROOF_FIXTURES.panel;
  log.push(`[Panel Proof] Initial state: is_expanded = ${panelFix.uiState.is_expanded}`);

  // Test Display: hidden initially, with error border
  const dispExpanded = evaluateDisplayRule(panelFix.displayRules[0], panelFix.uiState, panelFix.slotValues, panelFix.nodeParams);
  const dispError = evaluateDisplayRule(panelFix.displayRules[1], panelFix.uiState, panelFix.slotValues, panelFix.nodeParams);
  log.push(`[Panel Proof] Initial visibility: '${dispExpanded.effect?.c}', error style: '${dispError.effect?.c}'`);
  if (dispExpanded.effect?.c !== 'hidden' || !dispError.effect?.c?.includes('border-oof')) {
    log.push("��� Panel Proof Error: Initial display rules evaluated incorrectly");
    success = false;
  }

  // Test Interaction: click toggle button
  const toggleRule = panelFix.interactionRules[0];
  const toggleRes = evaluateInteractionRule(toggleRule, {}, panelFix.uiState, panelFix.slotValues, panelFix.nodeParams);
  if (!toggleRes.success || !toggleRes.mutatedUiState) {
    log.push(`��� Panel Proof Error: Interaction toggle failed: ${JSON.stringify(toggleRes.diagnostics)}`);
    success = false;
  } else {
    log.push(`[Panel Proof] Mutated state: is_expanded = ${toggleRes.mutatedUiState.is_expanded}`);
    if (toggleRes.mutatedUiState.is_expanded !== true) {
      log.push("��� Panel Proof Error: is_expanded was not toggled to true");
      success = false;
    }
  }

  // 3. Security Boundary Violations (Fail-closed checks)
  log.push("[Security Proof] Running vulnerability payload tests...");

  // Violation case A: mutate a slot value (which is read-only)
  const badMutationRule: InteractionRule = ['on', 'click', [['set_ui_state', 'is_locked', true]]];
  const mutRes = evaluateInteractionRule(badMutationRule, {}, { active_tab: 'overview' }, { is_locked: false }, {});
  log.push(`[Security Proof] Mutate read-only slot result success = ${mutRes.success}`);
  if (mutRes.success) {
    log.push("��� Security Proof Error: Evaluator allowed write mutation to an undeclared UIState key (read-only check bypassed)");
    success = false;
  } else {
    log.push(`[Security Proof] Mutate slot diagnostics: '${mutRes.diagnostics[0].message}'`);
  }

  // Violation case B: unwhitelisted opcode (fetch)
  const fetchRule = ['on', 'click', [['fetch', 'https://example.com/api', {}]]] as any;
  const fetchRes = evaluateInteractionRule(fetchRule, {}, { active_tab: 'overview' }, {}, {});
  log.push(`[Security Proof] Banned opcode 'fetch' result success = ${fetchRes.success}`);
  if (fetchRes.success) {
    log.push("��� Security Proof Error: Evaluator permitted banned side-effect opcode 'fetch'");
    success = false;
  } else {
    log.push(`[Security Proof] Fetch diagnostics: '${fetchRes.diagnostics[0].message}'`);
  }

  // Violation case C: display rule with event domain reference
  const badDisplayRule = ['style', ['eq', ['event', 'value'], 'hack'], { c: 'bad' }, null] as any;
  const dispRes = evaluateDisplayRule(badDisplayRule, { active_tab: 'overview' }, {}, {});
  log.push(`[Security Proof] Event domain in display result success = ${dispRes.success}`);
  if (dispRes.success) {
    log.push("��� Security Proof Error: Evaluator permitted 'event' domain in display expression evaluation");
    success = false;
  } else {
    log.push(`[Security Proof] Event domain display diagnostics: '${dispRes.diagnostics[0].message}'`);
  }

  log.push(success ? "��� All GUI IR Verification Proofs Passed." : "��� Some GUI IR Proofs Failed.");
  return { success, log };
}
