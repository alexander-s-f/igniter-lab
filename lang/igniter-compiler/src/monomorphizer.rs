use crate::parser::{
    BlockBody, BodyDecl, ContractDecl, Expr, ExprOrBlock, SourceFile, Stmt, TypeRef, TypeRefNode,
};
use std::collections::HashMap;

pub fn monomorphize_program(parsed: &mut SourceFile) {
    let mut specialized_contracts = Vec::new();
    let mut generic_indices = Vec::new();

    for (idx, contract) in parsed.contracts.iter().enumerate() {
        if contract.type_params.is_empty() {
            continue;
        }

        // It is generic!
        generic_indices.push(idx);

        let type_param = &contract.type_params[0];
        let type_var = &type_param.name;
        if type_param.bounds.is_empty() {
            continue;
        }

        let bound_trait_ref = &type_param.bounds[0].trait_ref;
        let bound_trait_name = &bound_trait_ref.name;

        // Find matching trait decl to get its method names dynamically
        let trait_decl = parsed.traits.iter().find(|t| t.name == *bound_trait_name);
        let trait_method_name = trait_decl
            .and_then(|t| t.methods.first())
            .map(|m| m.name.clone())
            .unwrap_or_else(|| "add".to_string());

        // Find all impls matching this bound trait
        let matching_impls: Vec<_> = parsed
            .impls
            .iter()
            .filter(|imp| imp.trait_ref.name == *bound_trait_name)
            .collect();

        for imp in matching_impls {
            if imp.trait_ref.type_args.is_empty() {
                continue;
            }

            let concrete_type = &imp.trait_ref.type_args[0];
            let concrete_type_str = type_ref_to_string(concrete_type);
            let using_func = &imp.using.name;
            let assoc_types = &imp.associated_types;

            // Clone the generic contract
            let mut spec_contract = contract.clone();
            spec_contract.name = format!("{}[{}]", contract.name, concrete_type_str);
            spec_contract.type_params = Vec::new();
            spec_contract.specialization_of = Some(contract.name.clone());

            let mut type_args = HashMap::new();
            type_args.insert(type_var.clone(), concrete_type_str.clone());
            spec_contract.type_args = Some(type_args);

            // Specialization implements
            if let Some(mut impls_ref) = spec_contract.implements.clone() {
                for arg in &mut impls_ref.type_args {
                    substitute_type_ref(arg, type_var, concrete_type, assoc_types);
                }
                spec_contract.implements = Some(impls_ref);
            }

            // Look up shape
            let shape_name = spec_contract.implements.as_ref().map(|i| &i.name);
            let shape =
                shape_name.and_then(|name| parsed.contract_shapes.iter().find(|s| s.name == *name));

            let mut body = Vec::new();
            let mut inputs = Vec::new();
            let mut outputs = Vec::new();

            if let Some(sh) = shape {
                for port in &sh.body {
                    match port {
                        BodyDecl::Input {
                            name,
                            type_annotation,
                        } => {
                            let mut t = type_annotation.clone();
                            substitute_type_ref(&mut t, type_var, concrete_type, assoc_types);
                            inputs.push(BodyDecl::Input {
                                name: name.clone(),
                                type_annotation: t,
                            });
                        }
                        BodyDecl::Output {
                            name,
                            type_annotation,
                            lifecycle,
                            evidence,
                        } => {
                            let mut t = type_annotation.clone();
                            substitute_type_ref(&mut t, type_var, concrete_type, assoc_types);
                            outputs.push(BodyDecl::Output {
                                name: name.clone(),
                                type_annotation: t,
                                lifecycle: lifecycle.clone(),
                                evidence: evidence.clone(),
                            });
                        }
                        _ => {}
                    }
                }
            }

            body.extend(inputs);

            // Substitutions inside contract body compute nodes
            for decl in &contract.body {
                match decl {
                    BodyDecl::Compute {
                        name,
                        type_annotation,
                        expr,
                    } => {
                        let mut new_expr = expr.clone();
                        substitute_expr(&mut new_expr, &trait_method_name, using_func);

                        let mut new_type_annotation = type_annotation.clone();
                        if let Some(ref mut ta) = new_type_annotation {
                            substitute_type_ref(ta, type_var, concrete_type, assoc_types);
                        }

                        body.push(BodyDecl::Compute {
                            name: name.clone(),
                            type_annotation: new_type_annotation,
                            expr: new_expr,
                        });
                    }
                    other => {
                        body.push(other.clone());
                    }
                }
            }

            body.extend(outputs);
            spec_contract.body = body;

            specialized_contracts.push(spec_contract);
        }
    }

    if !generic_indices.is_empty() {
        // Filter out generic contracts and append specialized ones
        let mut new_contracts = Vec::new();
        for (idx, contract) in parsed.contracts.iter().enumerate() {
            if !generic_indices.contains(&idx) {
                new_contracts.push(contract.clone());
            }
        }
        new_contracts.extend(specialized_contracts);
        parsed.contracts = new_contracts;
    }
}

fn type_ref_to_string(tr: &TypeRef) -> String {
    match tr {
        TypeRef::Simple(s) => s.clone(),
        TypeRef::Structured { name, params, .. } => {
            if params.is_empty() {
                name.clone()
            } else {
                let param_strs: Vec<String> = params.iter().map(type_ref_to_string).collect();
                format!("{}[{}]", name, param_strs.join(","))
            }
        }
        TypeRef::DimsRecord { dims, .. } => {
            let mut parts: Vec<String> = dims
                .iter()
                .map(|(k, v)| format!("{}:{}", k, type_ref_to_string(v)))
                .collect();
            parts.sort();
            format!("Dims[{}]", parts.join(","))
        }
    }
}

fn substitute_type_ref(
    type_ref: &mut TypeRef,
    type_var: &str,
    concrete_type: &TypeRef,
    assoc_types: &HashMap<String, TypeRef>,
) {
    match type_ref {
        TypeRef::Simple(s) => {
            if s == type_var {
                *type_ref = concrete_type.clone();
            } else if s.starts_with(&format!("{}::", type_var)) {
                let assoc_name = s.strip_prefix(&format!("{}::", type_var)).unwrap();
                if let Some(assoc_ty) = assoc_types.get(assoc_name) {
                    *type_ref = assoc_ty.clone();
                }
            }
        }
        TypeRef::Structured { params, .. } => {
            for param in params {
                substitute_type_ref(param, type_var, concrete_type, assoc_types);
            }
        }
        TypeRef::DimsRecord { dims, .. } => {
            for val in dims.values_mut() {
                substitute_type_ref(val, type_var, concrete_type, assoc_types);
            }
        }
    }
}

fn substitute_expr(expr: &mut Expr, trait_method: &str, using_func: &str) {
    match expr {
        Expr::Call { fn_name, args } => {
            if fn_name == trait_method {
                *fn_name = using_func.to_string();
            }
            for arg in args {
                substitute_expr(arg, trait_method, using_func);
            }
        }
        Expr::BinaryOp { left, right, .. } => {
            substitute_expr(left, trait_method, using_func);
            substitute_expr(right, trait_method, using_func);
        }
        Expr::UnaryOp { operand, .. } => {
            substitute_expr(operand, trait_method, using_func);
        }
        Expr::FieldAccess { object, .. } => {
            substitute_expr(object, trait_method, using_func);
        }
        Expr::IndexAccess { object, index } => {
            substitute_expr(object, trait_method, using_func);
            substitute_expr(index, trait_method, using_func);
        }
        Expr::SliceRecord { fields } => {
            for val in fields.values_mut() {
                substitute_expr(val, trait_method, using_func);
            }
        }
        Expr::IfExpr {
            cond,
            then,
            else_block,
        } => {
            substitute_expr(cond, trait_method, using_func);
            for stmt in &mut then.stmts {
                substitute_statement(stmt, trait_method, using_func);
            }
            if let Some(ref mut e_expr) = then.return_expr {
                substitute_expr(e_expr, trait_method, using_func);
            }
            if let Some(else_b) = else_block {
                for stmt in &mut else_b.stmts {
                    substitute_statement(stmt, trait_method, using_func);
                }
                if let Some(ref mut e_expr) = else_b.return_expr {
                    substitute_expr(e_expr, trait_method, using_func);
                }
            }
        }
        Expr::Lambda { body, .. } => match &mut **body {
            ExprOrBlock::Expr(e) => substitute_expr(e, trait_method, using_func),
            ExprOrBlock::Block(block) => {
                for stmt in &mut block.stmts {
                    substitute_statement(stmt, trait_method, using_func);
                }
                if let Some(ref mut e_expr) = block.return_expr {
                    substitute_expr(e_expr, trait_method, using_func);
                }
            }
        },
        Expr::ArrayLiteral { items } => {
            for item in items {
                substitute_expr(item, trait_method, using_func);
            }
        }
        Expr::RecordLiteral { fields } => {
            for val in fields.values_mut() {
                substitute_expr(val, trait_method, using_func);
            }
        }
        _ => {}
    }
}

fn substitute_statement(stmt: &mut Stmt, trait_method: &str, using_func: &str) {
    match stmt {
        Stmt::Let { expr, .. } => substitute_expr(expr, trait_method, using_func),
        Stmt::ExprStmt { expr } => substitute_expr(expr, trait_method, using_func),
    }
}
