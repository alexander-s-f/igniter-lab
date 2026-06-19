use crate::parser::{Associativity, FormDecl, FormElement, SourceFile};
use std::collections::{HashMap, HashSet};

// ── Types ─────────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct FormEntry {
    pub id: String,       // e.g. "Add::infix"
    pub contract: String, // contract name
    pub module: Option<String>,
    pub trigger: String, // first distinguishing token: "+", ".sum", "for"
    pub kind: FormKind,
    pub elements: Vec<FormElement>,
    pub priority: i32,
    pub associativity: Associativity,
    pub trust_level: TrustLevel,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub inherited_from: Option<String>, // contract_shape name if inherited
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum FormKind {
    Infix,
    PrefixCall,
    PostfixMethod,
    MethodCall,
    BlockMethod,
    KeywordBlock,
    MultiKeyword,
    Unknown,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum TrustLevel {
    System,
    Stdlib,
    Trusted,
    User,
}

// ── Registry ──────────────────────────────────────────────────────────────────

#[derive(Debug, Default)]
pub struct FormRegistry {
    pub entries: Vec<FormEntry>,
    pub trigger_index: HashMap<String, Vec<usize>>, // trigger → indices into entries
    pub no_form_contracts: HashSet<String>,         // contracts with no_form modifier
    pub diagnostics: Vec<FormDiagnostic>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct FormDiagnostic {
    pub code: String,
    pub severity: String,
    pub message: String,
    pub contract: String,
}

impl FormRegistry {
    pub fn build_from_program(parsed: &SourceFile) -> Self {
        let mut registry = FormRegistry::default();
        let module = parsed.module.as_deref();

        for contract in &parsed.contracts {
            // Track no_form contracts for resolver-time blocking
            if contract.no_form {
                registry.no_form_contracts.insert(contract.name.clone());
            }

            for (form_idx, form) in contract.forms.iter().enumerate() {
                // Structural rules before registration
                if let Some(diag) = registry.check_structural_rules(form, &contract.name) {
                    registry.diagnostics.push(diag);
                    continue;
                }

                let trigger = derive_trigger(&form.elements);
                let kind = classify_form_kind(&form.elements);
                let id = format!("{}::{}", contract.name, form_id_suffix(&kind, form_idx));

                let entry = FormEntry {
                    id,
                    contract: contract.name.clone(),
                    module: module.map(|s| s.to_string()),
                    trigger: trigger.clone(),
                    kind,
                    elements: form.elements.clone(),
                    priority: form.priority,
                    associativity: form.associativity.clone(),
                    trust_level: TrustLevel::User,
                    inherited_from: None,
                };

                let idx = registry.entries.len();
                registry.entries.push(entry);
                registry.trigger_index.entry(trigger).or_default().push(idx);
            }

            // no_form check: if no_form=true AND forms non-empty → E-FORM-NOFM-DECL
            if contract.no_form && !contract.forms.is_empty() {
                registry.diagnostics.push(FormDiagnostic {
                    code: "E-FORM-NOFM-DECL".to_string(),
                    severity: "error".to_string(),
                    message: format!(
                        "contract '{}' has no_form modifier but also declares form annotations",
                        contract.name
                    ),
                    contract: contract.name.clone(),
                });
            }
        }

        // Inherit forms from contract_shapes
        for shape in &parsed.contract_shapes {
            for contract in &parsed.contracts {
                let implements_this_shape = contract
                    .implements
                    .as_ref()
                    .map_or(false, |imp| imp.name == shape.name);
                if !implements_this_shape {
                    continue;
                }

                for (form_idx, form) in shape.forms.iter().enumerate() {
                    let trigger = derive_trigger(&form.elements);
                    let kind = classify_form_kind(&form.elements);
                    let id = format!(
                        "{}::inherited_{}::{}",
                        contract.name,
                        shape.name,
                        form_id_suffix(&kind, form_idx)
                    );

                    let entry = FormEntry {
                        id,
                        contract: contract.name.clone(),
                        module: module.map(|s| s.to_string()),
                        trigger: trigger.clone(),
                        kind,
                        elements: form.elements.clone(),
                        priority: form.priority,
                        associativity: form.associativity.clone(),
                        trust_level: TrustLevel::User,
                        inherited_from: Some(shape.name.clone()),
                    };

                    let idx = registry.entries.len();
                    registry.entries.push(entry);
                    registry.trigger_index.entry(trigger).or_default().push(idx);
                }
            }
        }

        registry
    }

    // ── Structural rules (F-01, F-02, F-05) ──────────────────────────────────

    fn check_structural_rules(
        &self,
        form: &FormDecl,
        contract_name: &str,
    ) -> Option<FormDiagnostic> {
        let elements = &form.elements;

        // F-01: BlockRef must be preceded by at least one ArgRef or Literal
        let block_pos = elements
            .iter()
            .position(|e| matches!(e, FormElement::Block { .. }));
        if let Some(pos) = block_pos {
            if pos == 0 {
                return Some(FormDiagnostic {
                    code:     "E-FORM-STRUCT".to_string(),
                    severity: "error".to_string(),
                    message:  format!(
                        "contract '{}': block argument must be preceded by at least one arg or literal (F-01)",
                        contract_name
                    ),
                    contract: contract_name.to_string(),
                });
            }
        }

        // F-02: at most one BinderRef per form
        let binder_count = elements
            .iter()
            .filter(|e| matches!(e, FormElement::Binder { .. }))
            .count();
        if binder_count > 1 {
            return Some(FormDiagnostic {
                code: "E-FORM-BINDER".to_string(),
                severity: "error".to_string(),
                message: format!(
                    "contract '{}': at most one binder [x] allowed per form pattern (F-02)",
                    contract_name
                ),
                contract: contract_name.to_string(),
            });
        }

        // F-05: InfixForm token must be symbolic (not alphabetic identifier)
        // InfixForm = ArgRef Literal ArgRef
        if elements.len() == 3 {
            if let (
                FormElement::Arg { .. },
                FormElement::Literal { token },
                FormElement::Arg { .. },
            ) = (&elements[0], &elements[1], &elements[2])
            {
                if token
                    .chars()
                    .next()
                    .map_or(false, |c| c.is_alphabetic() || c == '_')
                {
                    return Some(FormDiagnostic {
                        code:     "E-FORM-KIND".to_string(),
                        severity: "error".to_string(),
                        message:  format!(
                            "contract '{}': InfixForm token '{}' must be symbolic, not alphabetic (F-05)",
                            contract_name, token
                        ),
                        contract: contract_name.to_string(),
                    });
                }
            }
        }

        None
    }

    pub fn to_form_table(&self, module: Option<&str>) -> serde_json::Value {
        let resolved: Vec<serde_json::Value> = self
            .entries
            .iter()
            .map(|e| {
                serde_json::json!({
                    "id":           e.id,
                    "trigger":      e.trigger,
                    "contract":     e.contract,
                    "kind":         e.kind,
                    "priority":     e.priority,
                    "associativity": e.associativity,
                    "trust_level":  e.trust_level,
                    "inherited_from": e.inherited_from,
                })
            })
            .collect();

        let diags: Vec<serde_json::Value> = self
            .diagnostics
            .iter()
            .map(|d| {
                serde_json::json!({
                    "code":     d.code,
                    "severity": d.severity,
                    "message":  d.message,
                    "contract": d.contract,
                })
            })
            .collect();

        serde_json::json!({
            "artifact":      "form_table",
            "module":        module,
            "entry_count":   self.entries.len(),
            "trigger_count": self.trigger_index.len(),
            "resolved":      resolved,
            "diagnostics":   diags,
        })
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

fn derive_trigger(elements: &[FormElement]) -> String {
    for elem in elements {
        match elem {
            FormElement::Literal { token } => return token.clone(),
            FormElement::Arg { .. } => continue, // skip leading args (postfix / infix)
            _ => break,
        }
    }
    // Fallback: use the first literal anywhere
    for elem in elements {
        if let FormElement::Literal { token } = elem {
            return token.clone();
        }
    }
    "<unknown>".to_string()
}

fn classify_form_kind(elements: &[FormElement]) -> FormKind {
    use FormElement::*;
    let has_block = elements.iter().any(|e| matches!(e, Block { .. }));
    let has_binder = elements.iter().any(|e| matches!(e, Binder { .. }));

    match elements {
        // (arg) "op" (arg)  — InfixForm
        [Arg { .. }, Literal { .. }, Arg { .. }] => FormKind::Infix,

        // "!" (arg) prefix unary
        [Literal { token }, Arg { .. }] if !token.starts_with('.') => FormKind::PrefixCall,

        // (arg) ".method"   — PostfixMethodForm
        [Arg { .. }, Literal { token }] if token.starts_with('.') => FormKind::PostfixMethod,

        // (arg) ".method" (arg)+ — MethodCallForm
        _ if elements.first().map_or(false, |e| matches!(e, Arg { .. }))
            && elements.get(1).map_or(
                false,
                |e| matches!(e, Literal { token } if token.starts_with('.')),
            )
            && !has_block
            && elements.len() > 2 =>
        {
            FormKind::MethodCall
        }

        // (arg) ".method" { (block) } — BlockMethodForm
        _ if elements.first().map_or(false, |e| matches!(e, Arg { .. }))
            && elements.get(1).map_or(
                false,
                |e| matches!(e, Literal { token } if token.starts_with('.')),
            )
            && has_block =>
        {
            FormKind::BlockMethod
        }

        // "keyword" ... { } — KeywordBlockForm / MultiKeywordForm
        _ if elements
            .first()
            .map_or(false, |e| matches!(e, Literal { .. }))
            && has_block
            && has_binder =>
        {
            FormKind::KeywordBlock
        }

        _ if elements
            .first()
            .map_or(false, |e| matches!(e, Literal { .. }))
            && has_block =>
        {
            FormKind::KeywordBlock
        }

        // "keyword" (arg)+ — keyword guard-style form (no block)
        _ if elements.first().map_or(false, |e| {
            matches!(e, Literal { token }
               if !token.starts_with('.'))
        }) && elements.iter().any(|e| matches!(e, Arg { .. })) =>
        {
            FormKind::KeywordBlock
        }

        _ => FormKind::Unknown,
    }
}

fn form_id_suffix(kind: &FormKind, idx: usize) -> String {
    let base = match kind {
        FormKind::Infix => "infix",
        FormKind::PrefixCall => "prefix_call",
        FormKind::PostfixMethod => "postfix",
        FormKind::MethodCall => "method_call",
        FormKind::BlockMethod => "block_method",
        FormKind::KeywordBlock => "keyword_block",
        FormKind::MultiKeyword => "multi_keyword",
        FormKind::Unknown => "unknown",
    };
    if idx == 0 {
        base.to_string()
    } else {
        format!("{}_{}", base, idx)
    }
}
