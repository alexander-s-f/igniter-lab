use crate::lexer::{Token, TokenType};
use std::collections::HashMap;

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct SourceFile {
    pub kind: String, // "parsed_program" or "source_file"
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source_path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source_hash: Option<String>,
    pub grammar_version: String,
    pub module: Option<String>,
    pub imports: Vec<Import>,
    pub traits: Vec<TraitDecl>,
    pub impls: Vec<ImplDecl>,
    pub contract_shapes: Vec<ContractShapeDecl>,
    pub contracts: Vec<ContractDecl>,
    pub types: Vec<TypeDecl>,
    pub functions: Vec<FunctionDecl>,
    pub pipelines: Vec<PipelineDecl>,
    pub olap_points: Vec<OlapPointDecl>,
    pub assumptions: Vec<AssumptionDecl>,
    pub parse_errors: Vec<ParseErrorDetail>,
}

// ── Form System ────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum FormElement {
    #[serde(rename = "arg")]
    Arg { name: String },
    #[serde(rename = "literal")]
    Literal { token: String },
    #[serde(rename = "block")]
    Block { name: String },
    #[serde(rename = "binder")]
    Binder { name: String },
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum Associativity {
    Left,
    Right,
    None,
}

impl Default for Associativity {
    fn default() -> Self { Associativity::Left }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct FormDecl {
    pub elements: Vec<FormElement>,
    pub priority: i32,
    pub associativity: Associativity,
}

// ── Import ─────────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct Import {
    pub module_path: String,
    pub names: Option<Vec<String>>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub hiding: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub overriding: Vec<String>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct TraitDecl {
    pub kind: String, // "trait"
    pub name: String,
    pub type_params: Vec<String>,
    pub methods: Vec<TraitMethod>,
    #[serde(default)]
    pub associated_types: Vec<String>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct TraitMethod {
    pub kind: String, // "trait_method"
    pub name: String,
    pub params: Vec<Param>,
    pub return_type: TypeRef,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ImplDecl {
    pub kind: String, // "impl"
    pub trait_ref: TypeRefNode,
    pub using: QualifiedRefContainer,
    #[serde(default)]
    pub associated_types: HashMap<String, TypeRef>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct QualifiedRefContainer {
    pub kind: String, // "qualified_ref"
    pub name: String,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct TypeRefNode {
    pub name: String,
    pub type_args: Vec<TypeRef>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ContractShapeDecl {
    pub kind: String, // "contract_shape"
    pub name: String,
    pub type_params: Vec<String>,
    pub body: Vec<BodyDecl>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub forms: Vec<FormDecl>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ContractDecl {
    pub kind: String, // "contract"
    pub name: String,
    pub modifier: String, // "pure", "observed", etc.
    pub type_params: Vec<ContractTypeParam>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub implements: Option<TypeRefNode>,
    pub body: Vec<BodyDecl>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub forms: Vec<FormDecl>,
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub no_form: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub specialization_of: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub type_args: Option<HashMap<String, String>>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ContractTypeParam {
    pub name: String,
    pub bounds: Vec<TypeParamBound>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct TypeParamBound {
    pub trait_ref: TypeRefNode,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(tag = "kind")]
pub enum BodyDecl {
    #[serde(rename = "input")]
    Input {
        name: String,
        type_annotation: TypeRef,
    },
    #[serde(rename = "capability")]
    Capability {
        name: String,
        type_annotation: TypeRef,
    },
    #[serde(rename = "effect")]
    Effect {
        name: String,
        capability_ref: String,
    },
    #[serde(rename = "output")]
    Output {
        name: String,
        type_annotation: TypeRef,
        #[serde(skip_serializing_if = "Option::is_none")]
        lifecycle: Option<String>,
        #[serde(skip_serializing_if = "Option::is_none")]
        evidence: Option<Vec<String>>,
    },
    #[serde(rename = "compute")]
    Compute {
        name: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        type_annotation: Option<TypeRef>,
        expr: Expr,
    },
    #[serde(rename = "read")]
    Read {
        name: String,
        type_annotation: TypeRef,
        from: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        lifecycle: Option<String>,
        #[serde(skip_serializing_if = "Option::is_none")]
        scoped_by: Option<String>,
        #[serde(skip_serializing_if = "Option::is_none")]
        cardinality: Option<Cardinality>,
        #[serde(skip_serializing_if = "Option::is_none")]
        schema_version: Option<String>,
        tenant_free: bool,
    },
    #[serde(rename = "snapshot")]
    Snapshot {
        name: String,
        expr: Expr,
        #[serde(skip_serializing_if = "Option::is_none")]
        lifecycle: Option<String>,
    },
    #[serde(rename = "window")]
    Window {
        label: String,
        options: HashMap<String, WindowValue>,
    },
    #[serde(rename = "escape")]
    Escape {
        name: String,
    },
    #[serde(rename = "stream")]
    Stream {
        name: String,
        type_annotation: TypeRef,
        fragment_class: String,      // "escape"
        escape_capability: String,   // "stream_input"
    },
    #[serde(rename = "fold_stream")]
    FoldStream {
        name: String,
        expr: Expr,
        #[serde(skip_serializing_if = "Option::is_none")]
        type_annotation: Option<TypeRef>,
        #[serde(skip_serializing_if = "Option::is_none")]
        bound: Option<StreamBound>,
    },
    #[serde(rename = "invariant")]
    Invariant {
        name: String,
        predicate_ref: String,
        severity: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        label: Option<String>,
        #[serde(skip_serializing_if = "Option::is_none")]
        message: Option<String>,
        #[serde(skip_serializing_if = "Option::is_none")]
        overridable_with: Option<String>,
    },
    #[serde(rename = "uses_assumptions")]
    UsesAssumptions {
        name: String,
    },
    #[serde(rename = "loop")]
    Loop {
        name: String,
        /// Canon item variable (G1: `loop Name item in source`).
        /// Empty string means no explicit item var — classifier falls back to singularize(source).
        #[serde(default, skip_serializing_if = "String::is_empty")]
        item: String,
        collection: Expr,
        #[serde(skip_serializing_if = "Option::is_none")]
        max_steps: Option<u64>,
        body: Vec<BodyDecl>,
    },
    #[serde(rename = "service_loop")]
    ServiceLoop {
        name: String,
        interval: ClockInterval,
        body: Vec<BodyDecl>,
    },
    /// G2: `decreases <variant>` inside recursive contract body
    #[serde(rename = "decreases")]
    Decreases {
        variant: String,
    },
    /// G2: `max_steps <N>` inside fuel_bounded (or recursive + decreases fuel) contract body
    #[serde(rename = "max_steps")]
    MaxSteps {
        value: u64,
    },
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ClockInterval {
    pub value: u64,
    pub unit: String,
}


#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct Cardinality {
    pub min: i64,
    pub max: i64,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(untagged)]
pub enum WindowValue {
    Int(i64),
    Float(f64),
    Str(String),
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(tag = "kind")]
pub enum StreamBound {
    #[serde(rename = "window_bounded")]
    WindowBounded,
    #[serde(rename = "count_bounded")]
    CountBounded { n: Option<i64> },
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct TypeDecl {
    pub kind: String, // "type"
    pub name: String,
    pub fields: Vec<FieldDecl>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct FieldDecl {
    pub name: String,
    pub type_annotation: TypeRef,
    pub optional: bool,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct FunctionDecl {
    pub kind: String, // "function"
    pub name: String,
    pub params: Vec<Param>,
    pub return_type: TypeRef,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub decreases: Option<String>,
    pub body: BlockBody,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct Param {
    pub name: String,
    pub type_annotation: TypeRef,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct BlockBody {
    pub stmts: Vec<Stmt>,
    pub return_expr: Option<Box<Expr>>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(tag = "kind")]
pub enum Stmt {
    #[serde(rename = "let")]
    Let {
        name: String,
        expr: Expr,
    },
    #[serde(rename = "expr_stmt")]
    ExprStmt {
        expr: Expr,
    },
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct PipelineDecl {
    pub kind: String, // "pipeline"
    pub name: String,
    pub in_type: TypeRef,
    pub out_type: TypeRef,
    pub err_type: TypeRef,
    pub steps: Vec<StepDecl>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct StepDecl {
    pub kind: String, // "step"
    pub name: String,
    pub ref_path: Option<String>, // "ref" in json
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct OlapPointDecl {
    pub kind: String, // "olap_point"
    pub name: String,
    pub dimensions: HashMap<String, TypeRef>,
    pub measure: TypeRef,
    pub granularity: HashMap<String, String>,
    pub source: Option<RawExpr>,
    pub indexed: Vec<String>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct RawExpr {
    pub kind: String, // "raw_expr"
    pub tokens: Vec<String>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct AssumptionDecl {
    pub kind: String, // "assumption_decl"
    pub name: String,
    pub fields: HashMap<String, serde_json::Value>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ParseErrorDetail {
    pub rule: String,
    pub severity: String,
    pub message: String,
    pub token: String,
    pub line: usize,
    pub col: usize,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(untagged)]
pub enum TypeRef {
    Simple(String),
    Structured {
        kind: String, // "type_ref"
        name: String,
        params: Vec<TypeRef>,
    },
    DimsRecord {
        kind: String, // "dims_record"
        dims: HashMap<String, TypeRef>,
    },
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(tag = "kind")]
pub enum Expr {
    #[serde(rename = "literal")]
    Literal {
        value: serde_json::Value,
        type_tag: String,
    },
    #[serde(rename = "ref")]
    Ref {
        name: String,
    },
    #[serde(rename = "binary_op")]
    BinaryOp {
        op: String,
        left: Box<Expr>,
        right: Box<Expr>,
    },
    #[serde(rename = "unary_op")]
    UnaryOp {
        op: String,
        operand: Box<Expr>,
    },
    #[serde(rename = "field_access")]
    FieldAccess {
        object: Box<Expr>,
        field: String,
    },
    #[serde(rename = "index_access")]
    IndexAccess {
        object: Box<Expr>,
        index: Box<Expr>, // Can also be SliceRecord
    },
    #[serde(rename = "slice_record")]
    SliceRecord {
        fields: HashMap<String, Expr>,
    },
    #[serde(rename = "call")]
    Call {
        #[serde(rename = "fn")]
        fn_name: String,
        args: Vec<Expr>,
    },
    #[serde(rename = "if_expr")]
    IfExpr {
        cond: Box<Expr>,
        then: BlockBody,
        #[serde(rename = "else")]
        else_block: Option<BlockBody>,
    },
    #[serde(rename = "lambda")]
    Lambda {
        params: Vec<String>,
        body: Box<ExprOrBlock>,
    },
    #[serde(rename = "array_literal")]
    ArrayLiteral {
        items: Vec<Expr>,
    },
    #[serde(rename = "record_literal")]
    RecordLiteral {
        fields: HashMap<String, Expr>,
    },
    #[serde(rename = "symbol")]
    Symbol {
        value: String,
    },
    #[serde(rename = "error")]
    Error {
        token: String,
    },
}

impl Expr {
    pub fn get_name(&self) -> Option<&str> {
        match self {
            Expr::Ref { name } => Some(name),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(untagged)]
pub enum ExprOrBlock {
    Expr(Expr),
    Block(BlockBody),
}

pub struct Parser {
    tokens: Vec<Token>,
    pos: usize,
    errors: Vec<ParseErrorDetail>,
    in_contract_body: bool,
}

impl Parser {
    pub fn new(tokens: Vec<Token>) -> Self {
        Self {
            tokens,
            pos: 0,
            errors: Vec::new(),
            in_contract_body: false,
        }
    }

    fn peek(&self, offset: usize) -> Option<&Token> {
        if self.pos + offset < self.tokens.len() {
            Some(&self.tokens[self.pos + offset])
        } else {
            None
        }
    }

    fn current(&self) -> Option<&Token> {
        self.peek(0)
    }

    fn advance(&mut self) -> Option<&Token> {
        if self.pos < self.tokens.len() {
            let tok = &self.tokens[self.pos];
            self.pos += 1;
            Some(tok)
        } else {
            None
        }
    }

    fn peek_type(&self, t_type: TokenType) -> bool {
        self.current().map_or(false, |t| t.token_type == t_type)
    }

    fn peek_value(&self, val: &str) -> bool {
        self.current().map_or(false, |t| t.value == val)
    }

    fn peek_kw(&self, kw: &str) -> bool {
        self.current().map_or(false, |t| t.token_type == TokenType::Keyword && t.value == kw)
    }

    fn peek_ident(&self) -> bool {
        self.current().map_or(false, |t| t.token_type == TokenType::Ident)
    }

    fn expect_type(&mut self, t_type: TokenType) -> Result<Token, String> {
        let tok = self.advance().ok_or_else(|| "Unexpected EOF".to_string())?;
        if tok.token_type == t_type {
            Ok(tok.clone())
        } else {
            Err(format!("Expected {:?}, got {:?}({}) at line {}, col {}", t_type, tok.token_type, tok.value, tok.line, tok.col))
        }
    }

    fn expect_kw(&mut self, kw: &str) -> Result<Token, String> {
        let tok = self.advance().ok_or_else(|| "Unexpected EOF".to_string())?;
        if tok.token_type == TokenType::Keyword && tok.value == kw {
            Ok(tok.clone())
        } else {
            Err(format!("Expected keyword '{}', got '{}' at line {}, col {}", kw, tok.value, tok.line, tok.col))
        }
    }

    fn expect_value(&mut self, val: &str) -> Result<Token, String> {
        let tok = self.advance().ok_or_else(|| "Unexpected EOF".to_string())?;
        if tok.value == val {
            Ok(tok.clone())
        } else {
            Err(format!("Expected '{}', got '{}' at line {}, col {}", val, tok.value, tok.line, tok.col))
        }
    }

    fn name_token(&mut self) -> Result<String, String> {
        let tok = self.advance().ok_or_else(|| "Unexpected EOF".to_string())?;
        if tok.token_type == TokenType::Ident || tok.token_type == TokenType::Keyword {
            Ok(tok.value.clone())
        } else {
            Err(format!("Expected name, got {:?}({})", tok.token_type, tok.value))
        }
    }

    fn add_parse_error(&mut self, rule: &str, message: &str, token: &str, line: usize, col: usize) {
        self.errors.push(ParseErrorDetail {
            rule: rule.to_string(),
            severity: "error".to_string(),
            message: message.to_string(),
            token: token.to_string(),
            line,
            col,
        });
    }

    pub fn parse(&mut self) -> SourceFile {
        let mut module = None;
        let mut imports = Vec::new();
        let mut traits = Vec::new();
        let mut impls = Vec::new();
        let mut contract_shapes = Vec::new();
        let mut contracts = Vec::new();
        let mut types = Vec::new();
        let mut functions = Vec::new();
        let mut pipelines = Vec::new();
        let mut olap_points = Vec::new();
        let mut assumptions = Vec::new();

        if self.peek_kw("module") {
            self.advance();
            if let Ok(path) = self.parse_module_path() {
                module = Some(path);
            }
        }

        while self.peek_kw("import") {
            self.advance();
            if let Ok(imp) = self.parse_import() {
                imports.push(imp);
            }
        }

        while !self.peek_type(TokenType::Eof) {
            match self.parse_top_decl() {
                Ok(Some(TopDecl::Trait(t))) => traits.push(t),
                Ok(Some(TopDecl::Impl(i))) => impls.push(i),
                Ok(Some(TopDecl::ContractShape(s))) => contract_shapes.push(s),
                Ok(Some(TopDecl::Contract(c))) => contracts.push(c),
                Ok(Some(TopDecl::Type(ty))) => types.push(ty),
                Ok(Some(TopDecl::Function(f))) => functions.push(f),
                Ok(Some(TopDecl::Pipeline(p))) => pipelines.push(p),
                Ok(Some(TopDecl::OlapPoint(o))) => olap_points.push(o),
                Ok(Some(TopDecl::Assumptions(mut a))) => assumptions.append(&mut a),
                _ => {
                    self.advance();
                }
            }
        }

        let grammar_version = self.determine_grammar_version(&contracts, &pipelines, &olap_points, &assumptions);

        SourceFile {
            kind: "parsed_program".to_string(),
            source_path: None,
            source_hash: None,
            grammar_version,
            module,
            imports,
            traits,
            impls,
            contract_shapes,
            contracts,
            types,
            functions,
            pipelines,
            olap_points,
            assumptions,
            parse_errors: self.errors.clone(),
        }
    }

    fn determine_grammar_version(&self, contracts: &[ContractDecl], pipelines: &[PipelineDecl], olaps: &[OlapPointDecl], assumptions: &[AssumptionDecl]) -> String {
        let is_decimal = |tr: &TypeRef| -> bool {
            match tr {
                TypeRef::Structured { name, .. } => name == "Decimal",
                _ => false,
            }
        };

        let has_uses_assumptions = contracts.iter().any(|c| {
            c.body.iter().any(|b| matches!(b, BodyDecl::UsesAssumptions { .. }))
        });

        if !assumptions.is_empty() || has_uses_assumptions {
            return "assumptions-v0".to_string();
        }

        if !olaps.is_empty() {
            return "olap-point-v0".to_string();
        }

        let has_decimal = contracts.iter().any(|c| {
            c.body.iter().any(|b| match b {
                BodyDecl::Input { type_annotation, .. } => is_decimal(type_annotation),
                BodyDecl::Output { type_annotation, .. } => is_decimal(type_annotation),
                BodyDecl::Read { type_annotation, .. } => is_decimal(type_annotation),
                BodyDecl::Compute { type_annotation: Some(ta), .. } => is_decimal(ta),
                _ => false,
            })
        });

        if has_decimal {
            return "decimal-v0".to_string();
        }

        let has_scoped = contracts.iter().any(|c| {
            c.body.iter().any(|b| match b {
                BodyDecl::Read { scoped_by: Some(_), .. } => true,
                _ => false,
            })
        });

        if !pipelines.is_empty() || has_scoped {
            return "spark-pipeline-v0".to_string();
        }

        let has_poly = !contracts.is_empty() && contracts.iter().any(|c| !c.type_params.is_empty());
        if has_poly {
            return "polymorphic-v0".to_string();
        }

        "0.1.0".to_string()
    }

    fn parse_module_path(&mut self) -> Result<String, String> {
        let mut parts = vec![self.name_token()?];
        while self.peek_type(TokenType::Dot) {
            self.advance();
            parts.push(self.name_token()?);
        }
        Ok(parts.join("."))
    }

    fn parse_import(&mut self) -> Result<Import, String> {
        let mut path_parts = vec![self.name_token()?];
        let mut names = None;

        loop {
            if self.peek_type(TokenType::Dot) && self.peek(1).map_or(false, |t| t.token_type == TokenType::LBrace) {
                self.advance(); self.advance();
                let mut n_list = Vec::new();
                while !self.peek_type(TokenType::RBrace) && !self.peek_type(TokenType::Eof) {
                    n_list.push(self.name_token()?);
                    if self.peek_type(TokenType::Comma) {
                        self.advance();
                    }
                }
                self.expect_type(TokenType::RBrace)?;
                names = Some(n_list);
                break;
            } else if self.peek_type(TokenType::Dot) && self.peek(1).map_or(false, |t| t.token_type == TokenType::Ident) {
                self.advance();
                path_parts.push(self.name_token()?);
            } else {
                break;
            }
        }

        let mut hiding = Vec::new();
        let mut overriding = Vec::new();

        if self.peek_kw("hiding") {
            self.advance();
            if self.peek_type(TokenType::LBracket) {
                self.advance();
                while !self.peek_type(TokenType::RBracket) && !self.peek_type(TokenType::Eof) {
                    let tok = self.advance().ok_or("EOF")?;
                    hiding.push(tok.value.clone());
                    if self.peek_type(TokenType::Comma) { self.advance(); }
                }
                let _ = self.expect_type(TokenType::RBracket);
            } else {
                let tok = self.advance().ok_or("EOF")?;
                hiding.push(tok.value.clone());
            }
        } else if self.peek_kw("overriding") {
            self.advance();
            let tok = self.advance().ok_or("EOF")?;
            overriding.push(tok.value.clone());
        }

        Ok(Import { module_path: path_parts.join("."), names, hiding, overriding })
    }

    fn parse_top_decl(&mut self) -> Result<Option<TopDecl>, String> {
        let tok = self.current().cloned().ok_or_else(|| "Unexpected EOF".to_string())?;
        match tok.value.as_str() {
            "trait" => { self.advance(); self.parse_trait_decl().map(|t| Some(TopDecl::Trait(t))) }
            "impl" => { self.advance(); self.parse_impl_decl().map(|i| Some(TopDecl::Impl(i))) }
            "contract_shape" => { self.advance(); self.parse_contract_shape_decl().map(|s| Some(TopDecl::ContractShape(s))) }
            "contract" => { self.advance(); self.parse_contract_decl(None).map(|c| Some(TopDecl::Contract(c))) }
            "pure" | "observed" | "effect" | "privileged" | "irreversible"
            // G2: recursive/fuel_bounded contract modifiers (PROP-039 gate 3)
            | "recursive" | "fuel_bounded" => {
                let modifier = tok.value.clone();
                self.advance();
                if self.peek_kw("contract") {
                    self.advance();
                    self.parse_contract_decl(Some(modifier)).map(|c| Some(TopDecl::Contract(c)))
                } else {
                    self.add_parse_error("OOF-P0", &format!("Expected 'contract' after modifier '{}'", modifier), &modifier, tok.line, tok.col);
                    Err("Expected contract after modifier".to_string())
                }
            }
            "type" => { self.advance(); self.parse_type_decl().map(|ty| Some(TopDecl::Type(ty))) }
            "def" => { self.advance(); self.parse_function_decl().map(|f| Some(TopDecl::Function(f))) }
            "pipeline" => { self.advance(); self.parse_pipeline_decl().map(|p| Some(TopDecl::Pipeline(p))) }
            "olap_point" => { self.advance(); self.parse_olap_point_decl().map(|o| Some(TopDecl::OlapPoint(o))) }
            "assumptions" => { self.advance(); self.parse_assumptions_block().map(|a| Some(TopDecl::Assumptions(a))) }
            _ => {
                self.add_parse_error("OOF-G1", &format!("Unexpected top-level token: {}", tok.value), &tok.value, tok.line, tok.col);
                self.advance();
                Ok(None)
            }
        }
    }

    fn parse_assumptions_block(&mut self) -> Result<Vec<AssumptionDecl>, String> {
        self.expect_type(TokenType::LBrace)?;
        let mut assumptions = Vec::new();
        while !self.peek_type(TokenType::RBrace) && !self.peek_type(TokenType::Eof) {
            let tok = self.current().cloned();
            if self.peek_kw("assumption") {
                self.advance();
                if let Some(tok) = tok {
                    if let Ok(a) = self.parse_assumption_decl(tok) {
                        assumptions.push(a);
                    }
                }
            } else {
                let current_tok = self.current().cloned().unwrap_or_else(|| Token { token_type: TokenType::Eof, value: String::new(), line: 0, col: 0 });
                self.add_parse_error("OOF-P0", "Expected 'assumption' declaration inside assumptions block", &current_tok.value, current_tok.line, current_tok.col);
                self.advance();
            }
        }
        self.expect_type(TokenType::RBrace)?;
        Ok(assumptions)
    }

    fn parse_assumption_decl(&mut self, assumption_tok: Token) -> Result<AssumptionDecl, String> {
        if !self.peek_ident() {
            let val = self.current().map_or("", |t| &t.value).to_string();
            self.add_parse_error("OOF-P28", "assumption declaration requires a name", &val, assumption_tok.line, assumption_tok.col);
            if self.peek_type(TokenType::LBrace) {
                self.skip_balanced_block();
            }
            return Err("Assumption name missing".to_string());
        }

        let name = self.name_token()?;
        self.expect_type(TokenType::LBrace)?;
        let mut fields = HashMap::new();
        while !self.peek_type(TokenType::RBrace) && !self.peek_type(TokenType::Eof) {
            let field_tok = self.current().cloned().ok_or("EOF")?;
            let field = self.name_token()?;
            if self.peek_type(TokenType::Colon) {
                self.advance();
            }
            let val = self.parse_assumption_field_value(&field, field_tok)?;
            fields.insert(field, val);
            if self.peek_type(TokenType::Comma) {
                self.advance();
            }
        }
        self.expect_type(TokenType::RBrace)?;
        Ok(AssumptionDecl {
            kind: "assumption_decl".to_string(),
            name,
            fields,
        })
    }

    fn parse_assumption_field_value(&mut self, field: &str, field_tok: Token) -> Result<serde_json::Value, String> {
        match field {
            "kind" => {
                if self.peek_type(TokenType::SymbolLit) {
                    Ok(serde_json::Value::String(self.advance().unwrap().value.clone()))
                } else {
                    self.add_parse_error("OOF-P0", "assumption kind requires a symbol literal", field, field_tok.line, field_tok.col);
                    Ok(serde_json::Value::Null)
                }
            }
            "statement" | "source" => {
                if self.peek_type(TokenType::StringLit) {
                    Ok(serde_json::Value::String(self.advance().unwrap().value.clone()))
                } else if self.peek_type(TokenType::NilLit) {
                    self.advance();
                    Ok(serde_json::Value::Null)
                } else {
                    self.add_parse_error("OOF-P0", &format!("assumption {} requires a string literal", field), field, field_tok.line, field_tok.col);
                    Ok(serde_json::Value::Null)
                }
            }
            "strength" => {
                if self.peek_type(TokenType::FloatLit) {
                    let val = self.advance().unwrap().value.parse::<f64>().unwrap_or(0.0);
                    Ok(serde_json::Value::Number(serde_json::Number::from_f64(val).unwrap()))
                } else if self.peek_type(TokenType::IntLit) {
                    let val = self.advance().unwrap().value.parse::<i64>().unwrap_or(0);
                    Ok(serde_json::Value::Number(serde_json::Number::from(val)))
                } else {
                    self.add_parse_error("OOF-P0", "assumption strength requires a numeric literal", "strength", field_tok.line, field_tok.col);
                    Ok(serde_json::Value::Null)
                }
            }
            _ => {
                self.add_parse_error("OOF-P0", &format!("Unknown assumption field: {}", field), field, field_tok.line, field_tok.col);
                Ok(serde_json::Value::Null)
            }
        }
    }

    fn parse_pipeline_decl(&mut self) -> Result<PipelineDecl, String> {
        let name_tok = self.current().cloned().ok_or("EOF")?;
        let name = self.name_token()?;
        self.expect_type(TokenType::LBracket)?;
        let in_type = self.parse_type_ref()?;
        self.expect_type(TokenType::Comma)?;
        let out_type = self.parse_type_ref()?;
        self.expect_type(TokenType::Comma)?;
        let err_type = self.parse_type_ref()?;
        self.expect_type(TokenType::RBracket)?;
        self.expect_type(TokenType::LBrace)?;

        let mut steps = Vec::new();
        while !self.peek_type(TokenType::RBrace) && !self.peek_type(TokenType::Eof) {
            if self.peek_kw("step") {
                self.advance();
                let s_tok = self.current().cloned().ok_or("EOF")?;
                let s_name = self.name_token()?;
                if self.peek_type(TokenType::Colon) {
                    self.advance();
                    let ref_path = self.parse_qualified_ref()?;
                    steps.push(StepDecl {
                        kind: "step".to_string(),
                        name: s_name,
                        ref_path: Some(ref_path),
                    });
                } else {
                    self.add_parse_error("OOF-PG2", "step must reference a contract", &s_name, s_tok.line, s_tok.col);
                    self.skip_optional_block_or_step_tail();
                    steps.push(StepDecl {
                        kind: "step".to_string(),
                        name: s_name,
                        ref_path: None,
                    });
                }
            } else {
                let tok = self.current().cloned().ok_or("EOF")?;
                self.add_parse_error("OOF-P0", &format!("Expected 'step', got '{}'", tok.value), &tok.value, tok.line, tok.col);
                self.advance();
            }
        }

        if steps.is_empty() {
            self.add_parse_error("OOF-PG1", "pipeline must contain at least one step", &name, name_tok.line, name_tok.col);
        }

        self.expect_type(TokenType::RBrace)?;

        Ok(PipelineDecl {
            kind: "pipeline".to_string(),
            name,
            in_type,
            out_type,
            err_type,
            steps,
        })
    }

    fn parse_olap_point_decl(&mut self) -> Result<OlapPointDecl, String> {
        let name_tok = self.current().cloned().ok_or("EOF")?;
        let name = self.name_token()?;
        self.expect_type(TokenType::LBrace)?;

        let mut dimensions = HashMap::new();
        let mut measure = None;
        let mut granularity = HashMap::new();
        let mut source = None;
        let mut indexed = Vec::new();

        while !self.peek_type(TokenType::RBrace) && !self.peek_type(TokenType::Eof) {
            let clause_tok = self.current().cloned().ok_or("EOF")?;
            let clause = self.name_token()?;
            self.expect_type(TokenType::Colon)?;

            match clause.as_str() {
                "dimensions" => {
                    dimensions = self.parse_olap_type_map()?;
                }
                "measure" => {
                    measure = Some(self.parse_type_ref()?);
                }
                "granularity" => {
                    granularity = self.parse_olap_symbol_map()?;
                }
                "source" => {
                    source = self.parse_olap_source_expr()?;
                }
                "indexed" => {
                    indexed = self.parse_olap_symbol_list()?;
                }
                _ => {
                    self.add_parse_error("OOF-P0", &format!("Unknown olap_point clause: {}", clause), &clause, clause_tok.line, clause_tok.col);
                    self.skip_until_olap_clause_boundary();
                }
            }
        }

        if dimensions.is_empty() {
            self.add_parse_error("OOF-P0", &format!("olap_point '{}' must declare dimensions", name), &name, name_tok.line, name_tok.col);
        }
        if measure.is_none() {
            self.add_parse_error("OOF-P0", &format!("olap_point '{}' must declare measure", name), &name, name_tok.line, name_tok.col);
        }

        self.expect_type(TokenType::RBrace)?;

        Ok(OlapPointDecl {
            kind: "olap_point".to_string(),
            name,
            dimensions,
            measure: measure.unwrap_or(TypeRef::Simple("Unknown".to_string())),
            granularity,
            source,
            indexed,
        })
    }

    fn parse_olap_type_map(&mut self) -> Result<HashMap<String, TypeRef>, String> {
        self.expect_type(TokenType::LBrace)?;
        let mut map = HashMap::new();
        while !self.peek_type(TokenType::RBrace) && !self.peek_type(TokenType::Eof) {
            let key = self.name_token()?;
            self.expect_type(TokenType::Colon)?;
            let val = self.parse_type_ref()?;
            map.insert(key, val);
            if self.peek_type(TokenType::Comma) {
                self.advance();
            }
        }
        self.expect_type(TokenType::RBrace)?;
        Ok(map)
    }

    fn parse_olap_symbol_map(&mut self) -> Result<HashMap<String, String>, String> {
        self.expect_type(TokenType::LBrace)?;
        let mut map = HashMap::new();
        while !self.peek_type(TokenType::RBrace) && !self.peek_type(TokenType::Eof) {
            let key = self.name_token()?;
            self.expect_type(TokenType::Colon)?;
            let val = self.parse_olap_symbol_value()?;
            map.insert(key, val);
            if self.peek_type(TokenType::Comma) {
                self.advance();
            }
        }
        self.expect_type(TokenType::RBrace)?;
        Ok(map)
    }

    fn parse_olap_symbol_list(&mut self) -> Result<Vec<String>, String> {
        self.expect_type(TokenType::LBracket)?;
        let mut list = Vec::new();
        while !self.peek_type(TokenType::RBracket) && !self.peek_type(TokenType::Eof) {
            list.push(self.parse_olap_symbol_value()?);
            if self.peek_type(TokenType::Comma) {
                self.advance();
            }
        }
        self.expect_type(TokenType::RBracket)?;
        Ok(list)
    }

    fn parse_olap_symbol_value(&mut self) -> Result<String, String> {
        let tok = self.advance().ok_or_else(|| "Unexpected EOF".to_string())?;
        if tok.token_type == TokenType::SymbolLit || tok.token_type == TokenType::Ident || tok.token_type == TokenType::Keyword {
            Ok(tok.value.clone())
        } else {
            Err("Expected symbol or identifier".to_string())
        }
    }

    fn parse_olap_source_expr(&mut self) -> Result<Option<RawExpr>, String> {
        let mut tokens = Vec::new();
        let mut depth = 0;
        while let Some(tok) = self.current() {
            if depth == 0 && (tok.token_type == TokenType::RBrace || self.is_olap_clause_boundary()) {
                break;
            }
            let tok = self.advance().cloned().ok_or("EOF")?;
            if matches!(tok.token_type, TokenType::LBrace | TokenType::LParen | TokenType::LBracket) {
                depth += 1;
            }
            if matches!(tok.token_type, TokenType::RBrace | TokenType::RParen | TokenType::RBracket) {
                depth -= 1;
            }
            tokens.push(tok.value.clone());
        }
        if tokens.is_empty() {
            Ok(None)
        } else {
            Ok(Some(RawExpr {
                kind: "raw_expr".to_string(),
                tokens,
            }))
        }
    }

    fn is_olap_clause_boundary(&self) -> bool {
        if let Some(tok) = self.peek(0) {
            if matches!(tok.token_type, TokenType::Ident | TokenType::Keyword) {
                let clauses = ["dimensions", "measure", "granularity", "source", "indexed"];
                if clauses.contains(&tok.value.as_str()) {
                    if let Some(next) = self.peek(1) {
                        return next.token_type == TokenType::Colon;
                    }
                }
            }
        }
        false
    }

    fn parse_contract_decl(&mut self, modifier: Option<String>) -> Result<ContractDecl, String> {
        self.in_contract_body = true;
        let name = self.name_token()?;
        let type_params = if self.peek_type(TokenType::LBracket) {
            self.parse_contract_type_params()?
        } else {
            Vec::new()
        };
        let implements = if self.peek_kw("implements") {
            self.advance();
            Some(self.parse_type_ref_node(Vec::new())?)
        } else {
            None
        };

        let (forms, no_form) = self.parse_form_header_annotations();

        self.expect_type(TokenType::LBrace)?;
        let mut body = Vec::new();
        while !self.peek_type(TokenType::RBrace) && !self.peek_type(TokenType::Eof) {
            if let Some(b) = self.parse_body_decl() {
                body.push(b);
            }
        }
        self.expect_type(TokenType::RBrace)?;

        self.in_contract_body = false;
        Ok(ContractDecl {
            kind: "contract".to_string(),
            name,
            modifier: modifier.unwrap_or_else(|| "pure".to_string()),
            type_params,
            implements,
            body,
            forms,
            no_form,
            specialization_of: None,
            type_args: None,
        })
    }

    fn parse_contract_type_params(&mut self) -> Result<Vec<ContractTypeParam>, String> {
        self.expect_type(TokenType::LBracket)?;
        let mut params = Vec::new();
        while !self.peek_type(TokenType::RBracket) && !self.peek_type(TokenType::Eof) {
            let name = self.name_token()?;
            let mut bounds = Vec::new();
            if self.peek_type(TokenType::Colon) {
                self.advance();
                loop {
                    let trait_ref = self.parse_type_ref_node(vec![TypeRef::Simple(name.clone())])?;
                    bounds.push(TypeParamBound { trait_ref });
                    if self.peek_value("&") {
                        self.advance();
                    } else {
                        break;
                    }
                }
            }
            params.push(ContractTypeParam { name, bounds });
            if self.peek_type(TokenType::Comma) {
                self.advance();
            }
        }
        self.expect_type(TokenType::RBracket)?;
        Ok(params)
    }

    fn parse_type_ref_node(&mut self, default_type_args: Vec<TypeRef>) -> Result<TypeRefNode, String> {
        let name = self.name_token()?;
        let mut type_args = Vec::new();
        if self.peek_type(TokenType::LBracket) {
            self.advance();
            while !self.peek_type(TokenType::RBracket) && !self.peek_type(TokenType::Eof) {
                type_args.push(self.parse_type_ref()?);
                if self.peek_type(TokenType::Comma) {
                    self.advance();
                }
            }
            self.expect_type(TokenType::RBracket)?;
        } else {
            type_args = default_type_args;
        }
        Ok(TypeRefNode { name, type_args })
    }

    fn parse_body_decl(&mut self) -> Option<BodyDecl> {
        let tok = self.current()?.clone();
        match tok.value.as_str() {
            "input" => { self.advance(); self.parse_input_decl().ok() }
            "capability" => { self.advance(); self.parse_capability_decl().ok() }
            "effect" => { self.advance(); self.parse_effect_decl().ok() }
            "output" => { self.advance(); self.parse_output_decl().ok() }
            "compute" => { self.advance(); self.parse_compute_decl().ok() }
            "read" => { self.advance(); self.parse_read_decl().ok() }
            "snapshot" => { self.advance(); self.parse_snapshot_decl().ok() }
            "window" => { self.advance(); self.parse_window_decl().ok() }
            "escape" => { self.advance(); self.parse_escape_decl().ok() }
            "stream" => { self.advance(); self.parse_stream_decl().ok() }
            "fold_stream" => { self.advance(); self.parse_fold_stream_decl().ok() }
            "loop" => { self.advance(); self.parse_loop_or_service_loop_decl().ok() }
            // G3b: FiniteLoop — `for Name item in source { body }` (no max_steps; collection_exhaustion)
            "for" => { self.advance(); self.parse_for_loop_decl().ok() }
            "invariant" => { self.advance(); self.parse_invariant_decl().ok() }
            // G2: structural meta-declarations for recursive/fuel_bounded contracts
            "decreases" => { self.advance(); self.parse_decreases_body_decl().ok() }
            "max_steps" => { self.advance(); self.parse_max_steps_body_decl().ok() }
            "uses" => {
                self.advance();
                if self.peek_kw("assumptions") {
                    self.advance();
                    let name = self.name_token().ok()?;
                    Some(BodyDecl::UsesAssumptions { name })
                } else {
                    let current_tok = self.current().cloned().unwrap_or_else(|| Token { token_type: TokenType::Eof, value: String::new(), line: 0, col: 0 });
                    self.add_parse_error("OOF-P0", "uses declaration supports only 'uses assumptions NAME'", &current_tok.value, current_tok.line, current_tok.col);
                    self.skip_until_body_boundary();
                    None
                }
            }
            "pipeline" | "step" => {
                self.add_parse_error("OOF-P2", "pipeline/step is not valid inside a contract body", &tok.value, tok.line, tok.col);
                self.skip_invalid_body_decl();
                None
            }
            "scoped_by" => {
                self.add_parse_error("OOF-PG3", "scoped_by is only valid on read declarations", &tok.value, tok.line, tok.col);
                self.skip_invalid_body_decl();
                None
            }
            "tenant_free" => {
                self.add_parse_error("OOF-PG5", "tenant_free is only valid on read declarations", &tok.value, tok.line, tok.col);
                self.skip_invalid_body_decl();
                None
            }
            _ => {
                self.add_parse_error("OOF-P0", &format!("Unknown body declaration: {}", tok.value), &tok.value, tok.line, tok.col);
                self.advance();
                None
            }
        }
    }

    fn parse_input_decl(&mut self) -> Result<BodyDecl, String> {
        let name = self.name_token()?;
        self.expect_type(TokenType::Colon)?;
        let type_annotation = self.parse_type_ref()?;
        Ok(BodyDecl::Input { name, type_annotation })
    }

    fn parse_capability_decl(&mut self) -> Result<BodyDecl, String> {
        let name = self.name_token()?;
        self.expect_type(TokenType::Colon)?;
        let type_annotation = self.parse_type_ref()?;
        Ok(BodyDecl::Capability { name, type_annotation })
    }

    fn parse_effect_decl(&mut self) -> Result<BodyDecl, String> {
        let name = self.name_token()?;
        self.expect_value("using")?;
        let capability_ref = self.name_token()?;
        Ok(BodyDecl::Effect { name, capability_ref })
    }

    fn parse_output_decl(&mut self) -> Result<BodyDecl, String> {
        let name = self.name_token()?;
        self.expect_type(TokenType::Colon)?;
        let type_annotation = self.parse_type_ref()?;
        let lifecycle = if self.peek_kw("lifecycle") {
            self.advance();
            Some(self.parse_lifecycle_symbol()?)
        } else {
            None
        };
        let evidence = if self.peek_value("evidence") {
            Some(self.parse_evidence_list()?)
        } else {
            None
        };
        Ok(BodyDecl::Output { name, type_annotation, lifecycle, evidence })
    }

    fn parse_lifecycle_symbol(&mut self) -> Result<String, String> {
        let tok = self.advance().ok_or_else(|| "Unexpected EOF".to_string())?;
        if tok.token_type == TokenType::SymbolLit {
            Ok(tok.value.clone())
        } else {
            Err("Expected symbol for lifecycle".to_string())
        }
    }

    fn parse_evidence_list(&mut self) -> Result<Vec<String>, String> {
        self.expect_value("evidence")?;
        self.expect_type(TokenType::LBracket)?;
        let mut list = Vec::new();
        while !self.peek_type(TokenType::RBracket) && !self.peek_type(TokenType::Eof) {
            list.push(self.name_token()?);
            if self.peek_type(TokenType::Comma) {
                self.advance();
            }
        }
        self.expect_type(TokenType::RBracket)?;
        Ok(list)
    }

    fn parse_compute_decl(&mut self) -> Result<BodyDecl, String> {
        let name = self.name_token()?;
        let mut type_annotation = None;
        if self.peek_type(TokenType::Colon) {
            self.advance();
            type_annotation = Some(self.parse_type_ref()?);
        }
        self.expect_type(TokenType::Assign)?;
        let expr = self.parse_expr()?;
        
        if let Expr::Call { fn_name, .. } = &expr {
            if fn_name == "fold_stream" {
                if let Some(bound) = self.parse_optional_stream_bound() {
                    return Ok(BodyDecl::FoldStream {
                        name,
                        expr,
                        type_annotation,
                        bound: Some(bound),
                    });
                }
            }
        }

        Ok(BodyDecl::Compute { name, type_annotation, expr })
    }

    fn parse_read_decl(&mut self) -> Result<BodyDecl, String> {
        let name = self.name_token()?;
        self.expect_type(TokenType::Colon)?;
        let type_annotation = self.parse_type_ref()?;
        self.expect_kw("from")?;
        let from = self.expect_type(TokenType::StringLit)?.value;

        let mut lifecycle = None;
        let mut scoped_by = None;
        let mut cardinality = None;
        let mut schema_version = None;
        let mut tenant_free = false;

        loop {
            if self.peek_kw("lifecycle") {
                self.advance();
                lifecycle = Some(self.parse_lifecycle_symbol()?);
            } else if self.peek_kw("scoped_by") {
                self.advance();
                scoped_by = Some(self.name_token()?);
            } else if self.peek_kw("cardinality") {
                self.advance();
                cardinality = Some(self.parse_cardinality()?);
            } else if self.peek_kw("schema_version") {
                self.advance();
                schema_version = Some(self.expect_type(TokenType::StringLit)?.value);
            } else if self.peek_kw("tenant_free") {
                self.advance();
                tenant_free = true;
            } else {
                break;
            }
        }

        if tenant_free && scoped_by.is_some() {
            self.add_parse_error("OOF-PG3", &format!("scoped_by and tenant_free are mutually exclusive on read '{}'", name), &name, 0, 0);
        }

        Ok(BodyDecl::Read {
            name,
            type_annotation,
            from,
            lifecycle,
            scoped_by,
            cardinality,
            schema_version,
            tenant_free,
        })
    }

    fn parse_cardinality(&mut self) -> Result<Cardinality, String> {
        let min_tok = self.expect_type(TokenType::IntLit)?;
        if self.peek_type(TokenType::DotDot) {
            self.advance();
        } else {
            let tok = self.current().cloned().ok_or("EOF")?;
            self.add_parse_error("OOF-P0", &format!("Expected '..' in cardinality, got '{}'", tok.value), &tok.value, tok.line, tok.col);
        }
        let max_tok = self.expect_type(TokenType::IntLit)?;
        let min = min_tok.value.parse::<i64>().unwrap_or(0);
        let max = max_tok.value.parse::<i64>().unwrap_or(0);
        Ok(Cardinality { min, max })
    }

    fn parse_snapshot_decl(&mut self) -> Result<BodyDecl, String> {
        let name = self.name_token()?;
        self.expect_type(TokenType::Assign)?;
        let expr = self.parse_expr()?;
        let lifecycle = if self.peek_kw("lifecycle") {
            self.advance();
            Some(self.parse_lifecycle_symbol()?)
        } else {
            None
        };
        Ok(BodyDecl::Snapshot { name, expr, lifecycle })
    }

    fn parse_window_decl(&mut self) -> Result<BodyDecl, String> {
        let label = self.expect_type(TokenType::StringLit)?.value;
        self.expect_type(TokenType::LBrace)?;
        let mut options = HashMap::new();
        while !self.peek_type(TokenType::RBrace) && !self.peek_type(TokenType::Eof) {
            let key = self.name_token()?;
            if self.peek_type(TokenType::Colon) {
                self.advance();
            }
            let val = self.parse_window_value()?;
            options.insert(key, val);
            if self.peek_type(TokenType::Comma) {
                self.advance();
            }
        }
        self.expect_type(TokenType::RBrace)?;
        Ok(BodyDecl::Window { label, options })
    }

    fn parse_window_value(&mut self) -> Result<WindowValue, String> {
        let tok = self.advance().ok_or_else(|| "Unexpected EOF".to_string())?;
        match tok.token_type {
            TokenType::IntLit => Ok(WindowValue::Int(tok.value.parse::<i64>().unwrap_or(0))),
            TokenType::FloatLit => Ok(WindowValue::Float(tok.value.parse::<f64>().unwrap_or(0.0))),
            TokenType::SymbolLit | TokenType::Ident | TokenType::Keyword => Ok(WindowValue::Str(tok.value.clone())),
            _ => Err("Invalid window option value".to_string()),
        }
    }

    fn parse_escape_decl(&mut self) -> Result<BodyDecl, String> {
        let name = self.name_token()?;
        Ok(BodyDecl::Escape { name })
    }

    fn parse_invariant_decl(&mut self) -> Result<BodyDecl, String> {
        let name_tok = self.current().cloned().ok_or("EOF")?;
        let name = self.name_token()?;

        let mut predicate_ref = None;
        let mut severity = "error".to_string();
        let mut label = None;
        let mut message = None;
        let mut overridable_with = None;

        while self.peek_kw("predicate") || self.peek_kw("severity") || self.peek_kw("label") ||
              self.peek_kw("message") || self.peek_kw("overridable_with") {
            let attr_tok = self.current().cloned().ok_or("EOF")?;
            let attr = self.advance().unwrap().value.clone();
            self.expect_type(TokenType::Colon)?;

            match attr.as_str() {
                "predicate" => {
                    predicate_ref = Some(self.name_token()?);
                }
                "severity" => {
                    if self.peek_type(TokenType::SymbolLit) {
                        let sev = self.advance().unwrap().value.clone();
                        if ["error", "warn", "soft", "metric"].contains(&sev.as_str()) {
                            severity = sev;
                        } else {
                            self.add_parse_error("OOF-IV2", &format!("Unknown severity '{}'", sev), &sev, attr_tok.line, attr_tok.col);
                        }
                    } else {
                        let current_val = self.current().map_or("", |t| &t.value).to_string();
                        self.add_parse_error("OOF-IV2", "severity: requires a symbol literal", &current_val, attr_tok.line, attr_tok.col);
                    }
                }
                "label" => {
                    label = Some(if self.peek_type(TokenType::StringLit) { self.advance().unwrap().value.clone() } else { self.name_token()? });
                }
                "message" => {
                    message = Some(if self.peek_type(TokenType::StringLit) { self.advance().unwrap().value.clone() } else { self.name_token()? });
                }
                "overridable_with" => {
                    overridable_with = Some(if self.peek_type(TokenType::SymbolLit) { self.advance().unwrap().value.clone() } else { self.name_token()? });
                }
                _ => {}
            }
        }

        if predicate_ref.is_none() {
            self.add_parse_error("OOF-IV1", &format!("invariant '{}' missing required predicate: field", name), &name, name_tok.line, name_tok.col);
        }

        if overridable_with.is_some() && severity == "error" {
            self.add_parse_error("OOF-I4", ":error invariants cannot be overridden — use :warn", &name, name_tok.line, name_tok.col);
        }

        Ok(BodyDecl::Invariant {
            name,
            predicate_ref: predicate_ref.unwrap_or_default(),
            severity,
            label,
            message,
            overridable_with,
        })
    }

    fn parse_stream_decl(&mut self) -> Result<BodyDecl, String> {
        let name = self.name_token()?;
        self.expect_type(TokenType::Colon)?;
        let type_annotation = self.parse_type_ref()?;
        Ok(BodyDecl::Stream {
            name,
            type_annotation,
            fragment_class: "escape".to_string(),
            escape_capability: "stream_input".to_string(),
        })
    }

    fn parse_fold_stream_decl(&mut self) -> Result<BodyDecl, String> {
        let name_tok = self.current().cloned().ok_or("EOF")?;
        let name = self.name_token()?;
        self.expect_type(TokenType::Assign)?;
        let expr = self.parse_expr()?;
        let bound = self.parse_optional_stream_bound();

        if bound.is_none() {
            self.add_parse_error("OOF-S1", &format!("fold_stream '{}' is unbounded — must declare @window_bounded or @count_bounded(n)", name), &name, name_tok.line, name_tok.col);
        }

        Ok(BodyDecl::FoldStream {
            name,
            expr,
            type_annotation: None,
            bound,
        })
    }

    /// G2: parse `decreases <variant>` body declaration inside recursive contracts.
    /// variant may be a simple identifier ("fuel") or a dotted path ("items.remaining").
    fn parse_decreases_body_decl(&mut self) -> Result<BodyDecl, String> {
        let mut parts = Vec::new();
        // Collect the first identifier/keyword token
        if let Some(tok) = self.current().cloned() {
            if matches!(tok.token_type, TokenType::Ident | TokenType::Keyword) {
                parts.push(tok.value.clone());
                self.advance();
                // Collect dotted continuations (e.g. .remaining)
                while self.peek_type(TokenType::Dot) {
                    self.advance(); // consume dot
                    if let Some(next) = self.current().cloned() {
                        if matches!(next.token_type, TokenType::Ident | TokenType::Keyword) {
                            parts.push(next.value.clone());
                            self.advance();
                        } else {
                            break;
                        }
                    } else {
                        break;
                    }
                }
            }
        }
        let variant = if parts.is_empty() { "unknown".to_string() } else { parts.join(".") };
        Ok(BodyDecl::Decreases { variant })
    }

    /// G2: parse `max_steps <N>` body declaration inside fuel_bounded/recursive contracts.
    /// No colon — differs from loop-level `max_steps: N` form.
    fn parse_max_steps_body_decl(&mut self) -> Result<BodyDecl, String> {
        // Optional colon (allow both `max_steps 100` and `max_steps: 100` for tolerance)
        if self.peek_type(TokenType::Colon) {
            self.advance();
        }
        let tok = self.expect_type(TokenType::IntLit)?;
        let value = tok.value.parse::<u64>().unwrap_or(0);
        Ok(BodyDecl::MaxSteps { value })
    }

    fn parse_loop_or_service_loop_decl(&mut self) -> Result<BodyDecl, String> {
        let name_tok = self.current().cloned().ok_or("EOF")?;
        let name = self.name_token()?;
        if name.is_empty() {
            self.add_parse_error("OOF-L3", "Loop must have an explicit name (Postulate 28)", &name, name_tok.line, name_tok.col);
        }
        
        // G1 conformance: parse optional item variable before `in`
        // Canon form: `loop Name item in source`
        // Old form:   `loop Name in source`  (item="" → classifier falls back to singularize)
        let item = if !self.peek_kw("in") && !self.peek_type(TokenType::Eof) {
            self.name_token().unwrap_or_default()
        } else {
            String::new()
        };

        self.expect_kw("in")?;

        // If it's a clock.every service loop:
        if self.peek_kw("clock") {
            self.advance();
            self.expect_type(TokenType::Dot)?;
            self.expect_kw("every")?;
            self.expect_type(TokenType::LParen)?;
            let val_tok = self.expect_type(TokenType::IntLit)?;
            let val = val_tok.value.parse::<u64>().unwrap_or(1);
            self.expect_type(TokenType::Dot)?;
            let unit_tok = self.advance().ok_or_else(|| "Unexpected EOF".to_string())?;
            let unit = unit_tok.value.clone(); // seconds, minutes, hours
            self.expect_type(TokenType::RParen)?;
            
            self.expect_type(TokenType::LBrace)?;
            let mut body = Vec::new();
            while !self.peek_type(TokenType::RBrace) && !self.peek_type(TokenType::Eof) {
                if let Some(b) = self.parse_body_decl() {
                    body.push(b);
                }
            }
            self.expect_type(TokenType::RBrace)?;
            
            return Ok(BodyDecl::ServiceLoop {
                name,
                interval: ClockInterval { value: val, unit },
                body,
            });
        }
        
        // Normal loop:
        let collection = self.parse_expr()?;
        
        let mut max_steps = None;
        if self.peek_kw("max_steps") {
            self.advance();
            self.expect_type(TokenType::Colon)?;
            let steps_tok = self.expect_type(TokenType::IntLit)?;
            max_steps = Some(steps_tok.value.parse::<u64>().unwrap_or(100));
        }
        
        if max_steps.is_none() {
            self.add_parse_error("OOF-L1", &format!("loop '{}' is unbounded — must declare max_steps: N (Postulate 14)", name), &name, name_tok.line, name_tok.col);
        }
        
        self.expect_type(TokenType::LBrace)?;
        let mut body = Vec::new();
        while !self.peek_type(TokenType::RBrace) && !self.peek_type(TokenType::Eof) {
            if let Some(b) = self.parse_body_decl() {
                body.push(b);
            }
        }
        self.expect_type(TokenType::RBrace)?;
        
        Ok(BodyDecl::Loop {
            name,
            item,
            collection,
            max_steps,
            body,
        })
    }

    /// G3b: Parse `for Name item in source { body }` — FiniteLoop (no max_steps).
    /// Termination is via collection exhaustion (OOF-L1 fires if source is not Collection[T]).
    /// Reuses BodyDecl::Loop with max_steps=None; classifier derives loop_class="finite".
    fn parse_for_loop_decl(&mut self) -> Result<BodyDecl, String> {
        let name_tok = self.current().cloned().ok_or("EOF")?;
        let name = self.name_token()?;
        if name.is_empty() {
            self.add_parse_error("OOF-L3", "for loop must have an explicit name (Postulate 28)", &name, name_tok.line, name_tok.col);
        }

        // Canon form requires explicit item variable: `for Name item in source`
        let item = if !self.peek_kw("in") && !self.peek_type(TokenType::Eof) {
            self.name_token().unwrap_or_default()
        } else {
            String::new()
        };

        self.expect_kw("in")?;

        // Collection source (OOF-L1 fires at TypeChecker stage if not Collection[T])
        let collection = self.parse_expr()?;

        // No max_steps for FiniteLoop — termination is collection exhaustion

        self.expect_type(TokenType::LBrace)?;
        let mut body = Vec::new();
        while !self.peek_type(TokenType::RBrace) && !self.peek_type(TokenType::Eof) {
            if let Some(b) = self.parse_body_decl() {
                body.push(b);
            }
        }
        self.expect_type(TokenType::RBrace)?;

        Ok(BodyDecl::Loop {
            name,
            item,
            collection,
            max_steps: None,
            body,
        })
    }

    fn parse_optional_stream_bound(&mut self) -> Option<StreamBound> {
        if self.peek_type(TokenType::At) {
            self.advance();
            let b_tok = self.current().cloned().unwrap();
            let bound_name = self.name_token().ok()?;
            match bound_name.as_str() {
                "window_bounded" => Some(StreamBound::WindowBounded),
                "count_bounded" => {
                    self.expect_type(TokenType::LParen).ok()?;
                    let n = if self.peek_type(TokenType::IntLit) {
                        self.advance().unwrap().value.parse::<i64>().ok()
                    } else {
                        let cur_val = self.current().map_or("", |t| &t.value).to_string();
                        self.add_parse_error("OOF-S5", "@count_bounded requires a statically-known Integer literal", &cur_val, b_tok.line, b_tok.col);
                        None
                    };
                    self.expect_type(TokenType::RParen).ok()?;
                    Some(StreamBound::CountBounded { n })
                }
                _ => {
                    self.add_parse_error("OOF-S1", &format!("Unknown bound annotation '@{}'", bound_name), &bound_name, b_tok.line, b_tok.col);
                    None
                }
            }
        } else {
            None
        }
    }

    fn parse_type_decl(&mut self) -> Result<TypeDecl, String> {
        let name = self.name_token()?;
        self.expect_type(TokenType::LBrace)?;
        let mut fields = Vec::new();
        while !self.peek_type(TokenType::RBrace) && !self.peek_type(TokenType::Eof) {
            let fname = self.name_token()?;
            self.expect_type(TokenType::Colon)?;
            let ftype = self.parse_type_ref()?;
            let optional = if self.peek_type(TokenType::Question) {
                self.advance(); true
            } else {
                false
            };
            fields.push(FieldDecl {
                name: fname,
                type_annotation: ftype,
                optional,
            });
            if self.peek_type(TokenType::Comma) {
                self.advance();
            }
        }
        self.expect_type(TokenType::RBrace)?;
        Ok(TypeDecl {
            kind: "type".to_string(),
            name,
            fields,
        })
    }

    fn parse_trait_decl(&mut self) -> Result<TraitDecl, String> {
        let name = self.name_token()?;
        let type_params = if self.peek_type(TokenType::LBracket) {
            self.parse_simple_type_params()?
        } else {
            Vec::new()
        };
        self.expect_type(TokenType::LBrace)?;
        let mut methods = Vec::new();
        let mut associated_types = Vec::new();
        while !self.peek_type(TokenType::RBrace) && !self.peek_type(TokenType::Eof) {
            if self.peek_kw("type") {
                self.advance();
                let assoc_name = self.name_token()?;
                associated_types.push(assoc_name);
            } else {
                self.expect_kw("def")?;
                methods.push(self.parse_trait_method()?);
            }
        }
        self.expect_type(TokenType::RBrace)?;
        Ok(TraitDecl {
            kind: "trait".to_string(),
            name,
            type_params,
            methods,
            associated_types,
        })
    }

    fn parse_simple_type_params(&mut self) -> Result<Vec<String>, String> {
        self.expect_type(TokenType::LBracket)?;
        let mut list = Vec::new();
        while !self.peek_type(TokenType::RBracket) && !self.peek_type(TokenType::Eof) {
            list.push(self.name_token()?);
            if self.peek_type(TokenType::Comma) {
                self.advance();
            }
        }
        self.expect_type(TokenType::RBracket)?;
        Ok(list)
    }

    fn parse_trait_method(&mut self) -> Result<TraitMethod, String> {
        let name = self.name_token()?;
        let params = self.parse_params()?;
        self.expect_type(TokenType::Arrow)?;
        let return_type = self.parse_type_ref()?;
        Ok(TraitMethod {
            kind: "trait_method".to_string(),
            name,
            params,
            return_type,
        })
    }

    fn parse_params(&mut self) -> Result<Vec<Param>, String> {
        self.expect_type(TokenType::LParen)?;
        let mut params = Vec::new();
        while !self.peek_type(TokenType::RParen) && !self.peek_type(TokenType::Eof) {
            let pname = self.name_token()?;
            self.expect_type(TokenType::Colon)?;
            let ptype = self.parse_type_ref()?;
            params.push(Param { name: pname, type_annotation: ptype });
            if self.peek_type(TokenType::Comma) {
                self.advance();
            }
        }
        self.expect_type(TokenType::RParen)?;
        Ok(params)
    }

    fn parse_impl_decl(&mut self) -> Result<ImplDecl, String> {
        let trait_ref = self.parse_type_ref_node(Vec::new())?;
        self.expect_kw("using")?;
        let name = self.parse_qualified_ref()?;
        
        let mut associated_types = HashMap::new();
        if self.peek_type(TokenType::LBrace) {
            self.advance();
            while !self.peek_type(TokenType::RBrace) && !self.peek_type(TokenType::Eof) {
                self.expect_kw("type")?;
                let assoc_name = self.name_token()?;
                self.expect_type(TokenType::Assign)?;
                let assoc_type = self.parse_type_ref()?;
                associated_types.insert(assoc_name, assoc_type);
            }
            self.expect_type(TokenType::RBrace)?;
        }

        Ok(ImplDecl {
            kind: "impl".to_string(),
            trait_ref,
            using: QualifiedRefContainer {
                kind: "qualified_ref".to_string(),
                name,
            },
            associated_types,
        })
    }

    fn parse_contract_shape_decl(&mut self) -> Result<ContractShapeDecl, String> {
        let name = self.name_token()?;
        let type_params = if self.peek_type(TokenType::LBracket) {
            self.parse_simple_type_params()?
        } else {
            Vec::new()
        };

        let (forms, _no_form) = self.parse_form_header_annotations();

        self.expect_type(TokenType::LBrace)?;
        let mut body = Vec::new();
        while !self.peek_type(TokenType::RBrace) && !self.peek_type(TokenType::Eof) {
            let tok = self.current().cloned().ok_or("EOF")?;
            match tok.value.as_str() {
                "input" => { self.advance(); body.push(self.parse_input_decl()?); }
                "output" => { self.advance(); body.push(self.parse_output_decl()?); }
                _ => {
                    self.add_parse_error("OOF-P0", &format!("Unknown contract_shape declaration: {}", tok.value), &tok.value, tok.line, tok.col);
                    self.advance();
                }
            }
        }
        self.expect_type(TokenType::RBrace)?;
        Ok(ContractShapeDecl {
            kind: "contract_shape".to_string(),
            name,
            type_params,
            body,
            forms,
        })
    }

    fn parse_function_decl(&mut self) -> Result<FunctionDecl, String> {
        let name = self.name_token()?;
        let params = self.parse_params()?;
        self.expect_type(TokenType::Arrow)?;
        let return_type = self.parse_type_ref()?;
        
        let mut decreases = None;
        if self.peek_kw("decreases") {
            self.advance();
            let dec_val = self.name_token()?;
            decreases = Some(dec_val);
        }
        
        let body = self.parse_block_body()?;
        Ok(FunctionDecl {
            kind: "function".to_string(),
            name,
            params,
            return_type,
            decreases,
            body,
        })
    }

    fn parse_block_body(&mut self) -> Result<BlockBody, String> {
        self.expect_type(TokenType::LBrace)?;
        let mut stmts = Vec::new();
        let mut return_expr = None;
        while !self.peek_type(TokenType::RBrace) && !self.peek_type(TokenType::Eof) {
            if self.peek_kw("let") {
                stmts.push(self.parse_let_stmt()?);
            } else {
                let expr = self.parse_expr()?;
                if self.peek_type(TokenType::RBrace) {
                    return_expr = Some(Box::new(expr));
                    break;
                }
                stmts.push(Stmt::ExprStmt { expr });
            }
        }
        self.expect_type(TokenType::RBrace)?;
        Ok(BlockBody { stmts, return_expr })
    }

    fn parse_let_stmt(&mut self) -> Result<Stmt, String> {
        self.expect_kw("let")?;
        let name = self.name_token()?;
        self.expect_type(TokenType::Assign)?;
        let expr = self.parse_expr()?;
        Ok(Stmt::Let { name, expr })
    }

    fn parse_qualified_ref(&mut self) -> Result<String, String> {
        let mut parts = vec![self.name_token()?];
        while self.peek_type(TokenType::Dot) {
            self.advance();
            parts.push(self.name_token()?);
        }
        Ok(parts.join("."))
    }

    pub fn parse_type_ref(&mut self) -> Result<TypeRef, String> {
        let name_tok = self.current().cloned().ok_or("EOF")?;
        let mut name = self.name_token()?;
        if self.peek(0).map_or(false, |t| t.token_type == TokenType::Colon) &&
           self.peek(1).map_or(false, |t| t.token_type == TokenType::SymbolLit) {
            self.advance(); // consume Colon
            let sym_tok = self.advance().cloned().unwrap(); // consume SymbolLit
            name = format!("{}::{}", name, sym_tok.value);
        }
        if self.peek_type(TokenType::LBracket) {
            self.advance();
            if name == "Decimal" && self.peek_type(TokenType::IntLit) {
                let scale = self.advance().unwrap().value.parse::<i64>().unwrap_or(0);
                self.expect_type(TokenType::RBracket)?;
                return Ok(TypeRef::Structured {
                    kind: "type_ref".to_string(),
                    name: "Decimal".to_string(),
                    params: vec![TypeRef::Simple(scale.to_string())],
                });
            }
            let mut params = Vec::new();
            while !self.peek_type(TokenType::RBracket) && !self.peek_type(TokenType::Eof) {
                params.push(self.parse_type_ref_param(&name, params.len())?);
                if self.peek_type(TokenType::Comma) {
                    self.advance();
                }
            }
            self.expect_type(TokenType::RBracket)?;
            Ok(TypeRef::Structured {
                kind: "type_ref".to_string(),
                name,
                params,
            })
        } else {
            if name == "Decimal" {
                self.add_parse_error("OOF-DM3", "Decimal type requires scale parameter: Decimal[N]", &name, name_tok.line, name_tok.col);
                return Ok(TypeRef::Simple("Unknown".to_string()));
            }
            Ok(TypeRef::Simple(name))
        }
    }

    fn parse_type_ref_param(&mut self, parent_name: &str, index: usize) -> Result<TypeRef, String> {
        if parent_name == "OLAPPoint" && index == 1 && self.peek_type(TokenType::LBrace) {
            let dims = self.parse_olap_type_map()?;
            Ok(TypeRef::DimsRecord {
                kind: "dims_record".to_string(),
                dims,
            })
        } else {
            self.parse_type_ref()
        }
    }

    fn skip_optional_block_or_step_tail(&mut self) {
        if self.peek_type(TokenType::LBrace) {
            self.skip_balanced_block();
        } else {
            self.skip_until_body_boundary();
        }
    }

    fn skip_invalid_body_decl(&mut self) {
        self.advance();
        if self.peek_type(TokenType::LBrace) {
            self.skip_balanced_block();
        } else {
            self.skip_until_body_boundary();
        }
    }

    fn skip_balanced_block(&mut self) {
        if !self.peek_type(TokenType::LBrace) {
            return;
        }
        let mut depth = 0;
        loop {
            if let Some(tok) = self.advance() {
                if tok.token_type == TokenType::LBrace {
                    depth += 1;
                }
                if tok.token_type == TokenType::RBrace {
                    depth -= 1;
                }
                if depth <= 0 || tok.token_type == TokenType::Eof {
                    break;
                }
            } else {
                break;
            }
        }
    }

    fn skip_until_body_boundary(&mut self) {
        while let Some(tok) = self.current() {
            if tok.token_type == TokenType::RBrace || tok.token_type == TokenType::Eof || self.is_body_boundary_token(tok) {
                break;
            }
            self.advance();
        }
    }

    fn skip_until_olap_clause_boundary(&mut self) {
        while let Some(tok) = self.current() {
            if tok.token_type == TokenType::RBrace || tok.token_type == TokenType::Eof || self.is_olap_clause_boundary() {
                break;
            }
            self.advance();
        }
    }

    fn is_body_boundary_token(&self, tok: &Token) -> bool {
        if tok.token_type == TokenType::Keyword {
            let keywords = [
                "input", "output", "compute", "read", "snapshot", "window", "escape",
                "stream", "fold_stream", "invariant", "uses", "pipeline", "step",
                "scoped_by", "tenant_free"
            ];
            return keywords.contains(&tok.value.as_str());
        }
        false
    }

    // ── Form header parsing ───────────────────────────────────────────────────

    fn parse_form_header_annotations(&mut self) -> (Vec<FormDecl>, bool) {
        let mut forms: Vec<FormDecl> = Vec::new();
        let mut no_form = false;

        loop {
            if self.peek_kw("no_form") {
                self.advance();
                no_form = true;
            } else if self.peek_kw("form") {
                self.advance();
                let elements = self.parse_form_pattern();
                let mut decl = FormDecl { elements, priority: 5, associativity: Associativity::Left };
                // inline priority / associativity on the same logical line
                if self.peek_kw("priority") {
                    self.advance();
                    if let Ok(tok) = self.expect_type(TokenType::IntLit) {
                        decl.priority = tok.value.parse::<i32>().unwrap_or(5);
                    }
                }
                if self.peek_kw("associativity") {
                    self.advance();
                    if self.peek_type(TokenType::SymbolLit) {
                        let sym = self.advance().unwrap().value.clone();
                        decl.associativity = Self::parse_associativity(&sym);
                    }
                }
                forms.push(decl);
            } else if self.peek_kw("priority") && !forms.is_empty() {
                self.advance();
                if let Ok(tok) = self.expect_type(TokenType::IntLit) {
                    let p = tok.value.parse::<i32>().unwrap_or(5);
                    if let Some(last) = forms.last_mut() { last.priority = p; }
                }
            } else if self.peek_kw("associativity") && !forms.is_empty() {
                self.advance();
                if self.peek_type(TokenType::SymbolLit) {
                    let sym = self.advance().unwrap().value.clone();
                    let assoc = Self::parse_associativity(&sym);
                    if let Some(last) = forms.last_mut() { last.associativity = assoc; }
                }
            } else {
                break;
            }
        }

        (forms, no_form)
    }

    fn parse_associativity(sym: &str) -> Associativity {
        match sym {
            "right" => Associativity::Right,
            "none"  => Associativity::None,
            _       => Associativity::Left,
        }
    }

    fn parse_form_pattern(&mut self) -> Vec<FormElement> {
        let mut elements: Vec<FormElement> = Vec::new();

        loop {
            // Terminators: next annotation keyword, contract body, or EOF
            if self.peek_kw("priority") || self.peek_kw("associativity") ||
               self.peek_kw("form")     || self.peek_kw("no_form") ||
               self.peek_type(TokenType::Eof) {
                break;
            }

            if self.peek_type(TokenType::LBrace) {
                // Block element { (param) } — only if next is '('
                if self.peek(1).map_or(false, |t| t.token_type == TokenType::LParen) {
                    self.advance(); // consume {
                    self.advance(); // consume (
                    let name = self.name_token().unwrap_or_else(|_| "body".to_string());
                    let _ = self.expect_type(TokenType::RParen);
                    let _ = self.expect_type(TokenType::RBrace);
                    elements.push(FormElement::Block { name });
                } else {
                    break; // contract body starts here
                }
            } else if self.peek_type(TokenType::LParen) {
                // ArgRef (param)
                self.advance();
                let name = self.name_token().unwrap_or_else(|_| "arg".to_string());
                let _ = self.expect_type(TokenType::RParen);
                elements.push(FormElement::Arg { name });
            } else if self.peek_type(TokenType::LBracket) {
                // Binder [name]
                self.advance();
                let name = self.name_token().unwrap_or_else(|_| "it".to_string());
                let _ = self.expect_type(TokenType::RBracket);
                elements.push(FormElement::Binder { name });
            } else if self.peek_type(TokenType::StringLit) {
                let token = self.advance().unwrap().value.clone();
                elements.push(FormElement::Literal { token });
            } else {
                // Unknown token in form position — stop cleanly
                break;
            }
        }

        elements
    }

    // ── Expression parsing ────────────────────────────────────────────────────

    fn parse_expr(&mut self) -> Result<Expr, String> {
        self.parse_binary_or(0)
    }

    fn parse_binary_or(&mut self, min_prec: i32) -> Result<Expr, String> {
        let mut left = self.parse_unary()?;

        loop {
            let op = self.current().map(|t| t.value.clone());
            let prec = op.as_ref().and_then(|o| self.binary_prec(o));
            if prec.is_none() || prec.unwrap() < min_prec {
                break;
            }

            let op_tok = self.advance().unwrap().clone();
            let right = self.parse_binary_or(prec.unwrap() + 1)?;
            left = Expr::BinaryOp {
                op: op_tok.value,
                left: Box::new(left),
                right: Box::new(right),
            };
        }

        Ok(left)
    }

    fn binary_prec(&self, op: &str) -> Option<i32> {
        match op {
            "||" => Some(1),
            "&&" => Some(2),
            "==" | "!=" | "<" | ">" | "<=" | ">=" => Some(3),
            "++" => Some(4),
            "+" | "-" => Some(5),
            "*" | "/" => Some(6),
            _ => None,
        }
    }

    fn parse_unary(&mut self) -> Result<Expr, String> {
        if self.peek_type(TokenType::Bang) {
            let op = self.advance().unwrap().value.clone();
            let operand = self.parse_postfix()?;
            return Ok(Expr::UnaryOp {
                op,
                operand: Box::new(operand),
            });
        }
        self.parse_postfix()
    }

    fn parse_postfix(&mut self) -> Result<Expr, String> {
        let mut expr = self.parse_primary()?;

        loop {
            if self.peek_type(TokenType::Dot) {
                self.advance();
                let field = self.name_token()?;
                expr = Expr::FieldAccess {
                    object: Box::new(expr),
                    field,
                };
            } else if self.peek_type(TokenType::LBracket) {
                self.advance();
                let index = if self.index_slice_ahead() {
                    self.parse_index_slice_record()?
                } else {
                    self.parse_expr()?
                };
                self.expect_type(TokenType::RBracket)?;
                expr = Expr::IndexAccess {
                    object: Box::new(expr),
                    index: Box::new(index),
                };
            } else if self.peek_type(TokenType::LParen) {
                if let Expr::Ref { name } = &expr {
                    let fn_name = name.clone();
                    self.advance();
                    let mut args = Vec::new();
                    while !self.peek_type(TokenType::RParen) && !self.peek_type(TokenType::Eof) {
                        args.push(self.parse_call_arg()?);
                        if self.peek_type(TokenType::Comma) {
                            self.advance();
                        }
                    }
                    self.expect_type(TokenType::RParen)?;
                    expr = Expr::Call {
                        fn_name,
                        args,
                    };
                } else {
                    break;
                }
            } else {
                break;
            }
        }

        Ok(expr)
    }

    fn index_slice_ahead(&self) -> bool {
        if let Some(tok) = self.peek(0) {
            if matches!(tok.token_type, TokenType::Ident | TokenType::Keyword) {
                if let Some(next) = self.peek(1) {
                    return next.token_type == TokenType::Colon;
                }
            }
        }
        false
    }

    fn parse_index_slice_record(&mut self) -> Result<Expr, String> {
        let mut fields = HashMap::new();
        while !self.peek_type(TokenType::RBracket) && !self.peek_type(TokenType::Eof) {
            let key = self.name_token()?;
            self.expect_type(TokenType::Colon)?;
            let val = self.parse_expr()?;
            fields.insert(key, val);
            if self.peek_type(TokenType::Comma) {
                self.advance();
            }
        }
        Ok(Expr::SliceRecord { fields })
    }

    fn parse_call_arg(&mut self) -> Result<Expr, String> {
        if self.peek_type(TokenType::LParen) && self.lambda_ahead() {
            self.parse_lambda()
        } else if self.peek_type(TokenType::Ident) && self.peek(1).map_or(false, |t| t.token_type == TokenType::Arrow) {
            self.parse_lambda()
        } else {
            self.parse_expr()
        }
    }

    fn lambda_ahead(&self) -> bool {
        let mut depth = 0;
        let mut pos = self.pos;
        while pos < self.tokens.len() {
            let t = &self.tokens[pos];
            if t.token_type == TokenType::LParen {
                depth += 1;
            } else if t.token_type == TokenType::RParen {
                depth -= 1;
                if depth == 0 {
                    if pos + 1 < self.tokens.len() {
                        return self.tokens[pos + 1].token_type == TokenType::Arrow;
                    }
                    break;
                }
            } else if t.token_type == TokenType::Eof {
                break;
            }
            pos += 1;
        }
        false
    }

    fn parse_lambda(&mut self) -> Result<Expr, String> {
        let mut params = Vec::new();
        if self.peek_type(TokenType::LParen) {
            self.advance();
            while !self.peek_type(TokenType::RParen) && !self.peek_type(TokenType::Eof) {
                params.push(self.name_token()?);
                if self.peek_type(TokenType::Comma) {
                    self.advance();
                }
            }
            self.expect_type(TokenType::RParen)?;
        } else if self.peek_type(TokenType::Ident) {
            params.push(self.advance().unwrap().value.clone());
        }
        self.expect_type(TokenType::Arrow)?;
        let body = if self.peek_type(TokenType::LBrace) {
            ExprOrBlock::Block(self.parse_lambda_block()?)
        } else {
            ExprOrBlock::Expr(self.parse_expr()?)
        };
        Ok(Expr::Lambda {
            params,
            body: Box::new(body),
        })
    }

    fn parse_lambda_block(&mut self) -> Result<BlockBody, String> {
        self.expect_type(TokenType::LBrace)?;
        let mut stmts = Vec::new();
        let mut return_expr = None;
        while !self.peek_type(TokenType::RBrace) && !self.peek_type(TokenType::Eof) {
            if self.peek_kw("let") {
                stmts.push(self.parse_let_stmt()?);
            } else {
                let expr = self.parse_expr()?;
                if self.peek_type(TokenType::RBrace) {
                    return_expr = Some(Box::new(expr));
                    break;
                }
                stmts.push(Stmt::ExprStmt { expr });
            }
        }
        self.expect_type(TokenType::RBrace)?;
        Ok(BlockBody { stmts, return_expr })
    }

    fn parse_primary(&mut self) -> Result<Expr, String> {
        let tok = self.current().ok_or_else(|| "Unexpected EOF".to_string())?.clone();
        match tok.token_type {
            TokenType::Keyword => {
                match tok.value.as_str() {
                    "if" => {
                        self.advance();
                        self.parse_if_expr()
                    }
                    "true" => {
                        self.advance();
                        Ok(Expr::Literal { value: serde_json::Value::Bool(true), type_tag: "Bool".to_string() })
                    }
                    "false" => {
                        self.advance();
                        Ok(Expr::Literal { value: serde_json::Value::Bool(false), type_tag: "Bool".to_string() })
                    }
                    "nil" => {
                        self.advance();
                        Ok(Expr::Literal { value: serde_json::Value::Null, type_tag: "Nil".to_string() })
                    }
                    _ => {
                        self.advance();
                        Ok(Expr::Ref { name: tok.value })
                    }
                }
            }
            TokenType::Ident => {
                self.advance();
                if self.in_contract_body && tok.value == "now" {
                    self.add_parse_error("OOF-L2", "now() is forbidden in contract bodies — use explicit as_of binding or tick.time", "now", tok.line, tok.col);
                }
                Ok(Expr::Ref { name: tok.value })
            }
            TokenType::IntLit => {
                self.advance();
                let v = tok.value.parse::<i64>().unwrap_or(0);
                Ok(Expr::Literal { value: serde_json::Value::Number(serde_json::Number::from(v)), type_tag: "Integer".to_string() })
            }
            TokenType::FloatLit => {
                self.advance();
                let v = tok.value.parse::<f64>().unwrap_or(0.0);
                Ok(Expr::Literal { value: serde_json::Value::Number(serde_json::Number::from_f64(v).unwrap()), type_tag: "Float".to_string() })
            }
            TokenType::StringLit => {
                self.advance();
                Ok(Expr::Literal { value: serde_json::Value::String(tok.value), type_tag: "String".to_string() })
            }
            TokenType::SymbolLit => {
                self.advance();
                Ok(Expr::Symbol { value: tok.value })
            }
            TokenType::BoolLit => {
                self.advance();
                Ok(Expr::Literal { value: serde_json::Value::Bool(tok.value == "true"), type_tag: "Bool".to_string() })
            }
            TokenType::NilLit => {
                self.advance();
                Ok(Expr::Literal { value: serde_json::Value::Null, type_tag: "Nil".to_string() })
            }
            TokenType::LBracket => {
                self.parse_array_literal()
            }
            TokenType::LBrace => {
                self.parse_record_or_block()
            }
            TokenType::LParen => {
                self.advance();
                let expr = self.parse_expr()?;
                self.expect_type(TokenType::RParen)?;
                Ok(expr)
            }
            _ => {
                let err_tok = tok.value.clone();
                self.add_parse_error("OOF-P0", &format!("Unexpected token in expression: {:?}", tok.token_type), &err_tok, tok.line, tok.col);
                self.advance();
                Ok(Expr::Error { token: err_tok })
            }
        }
    }

    fn parse_if_expr(&mut self) -> Result<Expr, String> {
        let cond = self.parse_expr()?;
        let then = self.parse_block_body()?;
        let mut else_block = None;
        if self.peek_kw("else") {
            self.advance();
            else_block = Some(self.parse_block_body()?);
        }
        Ok(Expr::IfExpr {
            cond: Box::new(cond),
            then,
            else_block,
        })
    }

    fn parse_array_literal(&mut self) -> Result<Expr, String> {
        self.expect_type(TokenType::LBracket)?;
        let mut items = Vec::new();
        while !self.peek_type(TokenType::RBracket) && !self.peek_type(TokenType::Eof) {
            items.push(self.parse_expr()?);
            if self.peek_type(TokenType::Comma) {
                self.advance();
            }
        }
        self.expect_type(TokenType::RBracket)?;
        Ok(Expr::ArrayLiteral { items })
    }

    fn parse_record_or_block(&mut self) -> Result<Expr, String> {
        self.expect_type(TokenType::LBrace)?;
        let mut fields = HashMap::new();
        while !self.peek_type(TokenType::RBrace) && !self.peek_type(TokenType::Eof) {
            let key = self.name_token()?;
            self.expect_type(TokenType::Colon)?;
            let val = self.parse_expr()?;
            fields.insert(key, val);
            if self.peek_type(TokenType::Comma) {
                self.advance();
            }
        }
        self.expect_type(TokenType::RBrace)?;
        Ok(Expr::RecordLiteral { fields })
    }
}

pub enum TopDecl {
    Trait(TraitDecl),
    Impl(ImplDecl),
    ContractShape(ContractShapeDecl),
    Contract(ContractDecl),
    Type(TypeDecl),
    Function(FunctionDecl),
    Pipeline(PipelineDecl),
    OlapPoint(OlapPointDecl),
    Assumptions(Vec<AssumptionDecl>),
}
