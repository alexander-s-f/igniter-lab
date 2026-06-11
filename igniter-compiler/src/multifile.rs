use crate::lexer::Lexer;
use crate::parser::{Import, Parser, SourceFile};
use serde::Serialize;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, HashMap, HashSet};
use std::fs;

#[derive(Debug, Clone)]
pub struct SourceUnit {
    pub source_path: String,
    pub source: String,
    pub source_hash: String,
    pub parsed: SourceFile,
    pub module_path: String,
    pub imports: Vec<Import>,
    pub type_names: Vec<String>,
    pub contract_names: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct MergedProgram {
    pub source_path: String,
    pub source_hash: String,
    pub source: String,
    pub source_units: Vec<Value>,
}

#[derive(Debug, Clone, Serialize)]
pub struct MultifileDiagnostic {
    pub rule: String,
    pub severity: String,
    pub message: String,
    pub node: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source_path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub module_path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub import_path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub missing_name: Option<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub source_paths: Vec<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub module_paths: Vec<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub cycle_path: Vec<String>,
}

impl MultifileDiagnostic {
    fn new(rule: &str, message: String, node: String) -> Self {
        Self {
            rule: rule.to_string(),
            severity: "error".to_string(),
            message,
            node,
            source_path: None,
            module_path: None,
            import_path: None,
            missing_name: None,
            source_paths: Vec::new(),
            module_paths: Vec::new(),
            cycle_path: Vec::new(),
        }
    }

    pub fn to_value(&self) -> Value {
        serde_json::to_value(self).unwrap_or_else(|_| {
            json!({
                "rule": self.rule,
                "severity": self.severity,
                "message": self.message,
                "node": self.node
            })
        })
    }
}

pub fn compile_units(
    source_paths: &[String],
) -> std::io::Result<Result<MergedProgram, Vec<MultifileDiagnostic>>> {
    let mut units = Vec::new();
    for source_path in source_paths {
        units.push(read_source_unit(source_path)?);
    }

    if let Some(unit) = units.iter().find(|u| u.module_path.is_empty()) {
        let mut diag = MultifileDiagnostic::new(
            "OOF-IMP5",
            format!(
                "missing module declaration in multi-file source unit '{}'",
                unit.source_path
            ),
            "module".to_string(),
        );
        diag.source_path = Some(unit.source_path.clone());
        return Ok(Err(vec![diag]));
    }

    let sorted = sorted_units(&units);
    if let Some(diag) = duplicate_module_diagnostic(&sorted) {
        return Ok(Err(vec![diag]));
    }

    let by_module: HashMap<String, SourceUnit> = sorted
        .iter()
        .map(|unit| (unit.module_path.clone(), (*unit).clone()))
        .collect();

    let import_diags = validate_imports(&sorted, &by_module);
    if !import_diags.is_empty() {
        return Ok(Err(import_diags));
    }

    if let Some(diag) = circular_import_diagnostic(&sorted) {
        return Ok(Err(vec![diag]));
    }

    if let Some(diag) = duplicate_contract_diagnostic(&sorted) {
        return Ok(Err(vec![diag]));
    }
    if let Some(diag) = duplicate_type_diagnostic(&sorted) {
        return Ok(Err(vec![diag]));
    }

    let source_hash = composite_source_hash(&sorted);
    let source_path = format!(
        "multifile:{}",
        &source_hash.trim_start_matches("sha256:")[0..16]
    );
    let source_units = source_units_evidence(&sorted);
    let source = merged_source(&sorted);

    Ok(Ok(MergedProgram {
        source_path,
        source_hash,
        source,
        source_units,
    }))
}

fn read_source_unit(source_path: &str) -> std::io::Result<SourceUnit> {
    let source = fs::read_to_string(source_path)?;
    let source_hash = sha256(&source);
    let mut lexer = Lexer::new(&source);
    let tokens = lexer.tokenize();
    let mut parser = Parser::new(tokens);
    let mut parsed = parser.parse();
    parsed.source_path = Some(source_path.to_string());
    parsed.source_hash = Some(source_hash.clone());

    let module_path = parsed.module.clone().unwrap_or_default();
    let imports = parsed.imports.clone();
    let type_names = parsed.types.iter().map(|t| t.name.clone()).collect();
    let contract_names = parsed.contracts.iter().map(|c| c.name.clone()).collect();

    Ok(SourceUnit {
        source_path: source_path.to_string(),
        source,
        source_hash,
        parsed,
        module_path,
        imports,
        type_names,
        contract_names,
    })
}

fn sorted_units(units: &[SourceUnit]) -> Vec<SourceUnit> {
    let mut sorted = units.to_vec();
    sorted.sort_by(|a, b| {
        a.module_path
            .cmp(&b.module_path)
            .then(a.source_path.cmp(&b.source_path))
    });
    sorted
}

fn duplicate_module_diagnostic(units: &[SourceUnit]) -> Option<MultifileDiagnostic> {
    let mut by_module: HashMap<String, Vec<String>> = HashMap::new();
    for unit in units {
        by_module
            .entry(unit.module_path.clone())
            .or_default()
            .push(unit.source_path.clone());
    }

    let duplicate = by_module
        .iter()
        .filter(|(_, paths)| paths.len() > 1)
        .min_by(|a, b| a.0.cmp(b.0))?;

    let mut diag = MultifileDiagnostic::new(
        "OOF-IMP4",
        format!("duplicate module declaration '{}'", duplicate.0),
        format!("module:{}", duplicate.0),
    );
    diag.module_path = Some(duplicate.0.clone());
    diag.module_paths = vec![duplicate.0.clone()];
    diag.source_paths = duplicate.1.clone();
    Some(diag)
}

fn validate_imports(
    units: &[SourceUnit],
    by_module: &HashMap<String, SourceUnit>,
) -> Vec<MultifileDiagnostic> {
    let mut diagnostics = Vec::new();
    for unit in units {
        let mut imports = unit.imports.clone();
        imports.sort_by(|a, b| a.module_path.cmp(&b.module_path));
        for import in imports {
            let Some(target) = by_module.get(&import.module_path) else {
                let mut diag = MultifileDiagnostic::new(
                    "OOF-IMP2",
                    format!(
                        "unknown import path '{}' from module '{}'",
                        import.module_path, unit.module_path
                    ),
                    format!("import:{}", import.module_path),
                );
                diag.source_path = Some(unit.source_path.clone());
                diag.module_path = Some(unit.module_path.clone());
                diag.import_path = Some(import.module_path.clone());
                diagnostics.push(diag);
                continue;
            };

            if let Some(names) = import.names.as_ref() {
                let exported: HashSet<String> = target
                    .type_names
                    .iter()
                    .chain(target.contract_names.iter())
                    .cloned()
                    .collect();
                let mut missing: Vec<String> = names
                    .iter()
                    .filter(|name| !exported.contains(*name))
                    .cloned()
                    .collect();
                missing.sort();
                for name in missing {
                    let mut diag = MultifileDiagnostic::new(
                        "OOF-IMP3",
                        format!(
                            "unknown import name '{}' from '{}' in module '{}'",
                            name, import.module_path, unit.module_path
                        ),
                        format!("import:{}.{{{}}}", import.module_path, name),
                    );
                    diag.source_path = Some(unit.source_path.clone());
                    diag.module_path = Some(unit.module_path.clone());
                    diag.import_path = Some(import.module_path.clone());
                    diag.missing_name = Some(name);
                    diagnostics.push(diag);
                }
            }
        }
    }
    diagnostics
}

fn circular_import_diagnostic(units: &[SourceUnit]) -> Option<MultifileDiagnostic> {
    let graph: BTreeMap<String, Vec<String>> = units
        .iter()
        .map(|unit| {
            let mut deps: Vec<String> = unit
                .imports
                .iter()
                .map(|import| import.module_path.clone())
                .collect();
            deps.sort();
            (unit.module_path.clone(), deps)
        })
        .collect();

    let mut visiting = HashSet::new();
    let mut visited = HashSet::new();
    let mut stack = Vec::new();

    for module in graph.keys() {
        if let Some(cycle) = visit_cycle(module, &graph, &mut visiting, &mut visited, &mut stack) {
            let mut diag = MultifileDiagnostic::new(
                "OOF-IMP1",
                format!("circular import detected: {}", cycle.join(" -> ")),
                "import_cycle".to_string(),
            );
            diag.module_paths = cycle.clone();
            diag.cycle_path = cycle;
            return Some(diag);
        }
    }
    None
}

fn visit_cycle(
    module: &str,
    graph: &BTreeMap<String, Vec<String>>,
    visiting: &mut HashSet<String>,
    visited: &mut HashSet<String>,
    stack: &mut Vec<String>,
) -> Option<Vec<String>> {
    if visited.contains(module) {
        return None;
    }
    if visiting.contains(module) {
        let index = stack.iter().position(|m| m == module).unwrap_or(0);
        let mut cycle = stack[index..].to_vec();
        cycle.push(module.to_string());
        return Some(cycle);
    }

    visiting.insert(module.to_string());
    stack.push(module.to_string());

    if let Some(deps) = graph.get(module) {
        for dep in deps {
            if !graph.contains_key(dep) {
                continue;
            }
            if let Some(cycle) = visit_cycle(dep, graph, visiting, visited, stack) {
                return Some(cycle);
            }
        }
    }

    stack.pop();
    visiting.remove(module);
    visited.insert(module.to_string());
    None
}

fn duplicate_contract_diagnostic(units: &[SourceUnit]) -> Option<MultifileDiagnostic> {
    duplicate_declaration_diagnostic(units, "OOF-DECL-DUP-CONTRACT", "contract", |unit| {
        &unit.contract_names
    })
}

fn duplicate_type_diagnostic(units: &[SourceUnit]) -> Option<MultifileDiagnostic> {
    duplicate_declaration_diagnostic(units, "OOF-DECL-DUP-TYPE", "type", |unit| &unit.type_names)
}

fn duplicate_declaration_diagnostic<F>(
    units: &[SourceUnit],
    rule: &str,
    kind: &str,
    names_for: F,
) -> Option<MultifileDiagnostic>
where
    F: Fn(&SourceUnit) -> &Vec<String>,
{
    let mut owners: BTreeMap<String, Vec<&SourceUnit>> = BTreeMap::new();
    for unit in units {
        for name in names_for(unit) {
            owners.entry(name.clone()).or_default().push(unit);
        }
    }

    let (name, units) = owners.iter().find(|(_, owners)| owners.len() > 1)?;
    let mut diag = MultifileDiagnostic::new(
        rule,
        format!("duplicate {} declaration '{}'", kind, name),
        format!("{}:{}", kind, name),
    );
    diag.source_paths = units.iter().map(|unit| unit.source_path.clone()).collect();
    diag.module_paths = units.iter().map(|unit| unit.module_path.clone()).collect();
    Some(diag)
}

fn source_units_evidence(units: &[SourceUnit]) -> Vec<Value> {
    units
        .iter()
        .map(|unit| {
            json!({
                "module": unit.module_path,
                "source_path": unit.source_path,
                "source_hash": unit.source_hash,
                "types": unit.type_names,
                "contracts": unit.contract_names
            })
        })
        .collect()
}

fn composite_source_hash(units: &[SourceUnit]) -> String {
    let material: Vec<BTreeMap<String, String>> = units
        .iter()
        .map(|unit| {
            let mut item = BTreeMap::new();
            item.insert("module".to_string(), unit.module_path.clone());
            item.insert("source_path".to_string(), unit.source_path.clone());
            item.insert("source_hash".to_string(), unit.source_hash.clone());
            item.insert("source".to_string(), unit.source.clone());
            item
        })
        .collect();
    let json = serde_json::to_string(&material).unwrap_or_default();
    sha256(&json)
}

fn merged_source(units: &[SourceUnit]) -> String {
    let mut merged = String::from("module Lab.Multifile.Universe\n\n");
    for unit in units {
        merged.push_str(&format!("-- source_module: {}\n", unit.module_path));
        for line in unit.source.lines() {
            let trimmed = line.trim_start();
            if trimmed.starts_with("module ") || trimmed.starts_with("import ") {
                continue;
            }
            merged.push_str(line);
            merged.push('\n');
        }
        merged.push('\n');
    }
    merged
}

fn sha256(value: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(value.as_bytes());
    format!("sha256:{:x}", hasher.finalize())
}
