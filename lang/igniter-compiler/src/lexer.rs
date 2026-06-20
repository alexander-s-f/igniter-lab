#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TokenType {
    Keyword,
    Ident,
    StringLit,
    IntLit,
    FloatLit,
    BoolLit,
    NilLit,
    SymbolLit,
    LBrace,
    RBrace,
    LParen,
    RParen,
    LBracket,
    RBracket,
    Dot,
    DotDot,
    Comma,
    Colon,
    Arrow,    // ->
    FatArrow, // =>
    Op,       // +, -, *, /, ==, !=, <, >, <=, >=, &&, ||, ++
    Assign,   // =
    Pipe,     // |
    Question, // ?
    Bang,     // !
    At,       // @
    Illegal,  // a malformed lexeme (e.g. invalid string escape / unterminated string); `value` = reason
    Eof,
}

/// LAB-SRCMAP-P1: source location span for a single AST/SIR node.
/// v0: start positions exact (from lexer); end positions best-effort (0 = absent).
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct Span {
    pub start_line: usize,
    pub start_col: usize,
    pub end_line: usize,
    pub end_col: usize,
}

#[derive(Debug, Clone)]
pub struct Token {
    pub token_type: TokenType,
    pub value: String,
    pub line: usize,
    pub col: usize,
}

pub struct Lexer<'a> {
    source: &'a str,
    chars: Vec<char>,
    pos: usize,
    line: usize,
    col: usize,
}

const KEYWORDS: &[&str] = &[
    "module",
    "import",
    "contract",
    "contract_shape",
    "type",
    "def",
    "trait",
    "impl",
    "input",
    "output",
    "compute",
    "read",
    "snapshot",
    "window",
    "escape",
    "stream",
    "fold_stream",
    "assumptions",
    "assumption",
    "uses",
    "olap_point",
    "invariant",
    "predicate",
    "severity",
    "label",
    "message",
    "overridable_with",
    "from",
    "lifecycle",
    "using",
    "implements",
    "capability",
    "effect",
    "pipeline",
    "step",
    "scoped_by",
    "cardinality",
    "schema_version",
    "tenant_free",
    "variant",
    "match",
    "if",
    "else",
    "let",
    "true",
    "false",
    "nil",
    "and",
    "or",
    "not",
    "loop",
    "in",
    "max_steps",
    "decreases",
    "fuel",
    "clock",
    "every",
    "seconds",
    "minutes",
    "hours",
    "break",
    "form",
    "priority",
    "associativity",
    "no_form",
    "hiding",
    "overriding",
];

impl<'a> Lexer<'a> {
    pub fn new(source: &'a str) -> Self {
        Self {
            source,
            chars: source.chars().collect(),
            pos: 0,
            line: 1,
            col: 1,
        }
    }

    fn peek(&self, offset: usize) -> Option<char> {
        if self.pos + offset < self.chars.len() {
            Some(self.chars[self.pos + offset])
        } else {
            None
        }
    }

    fn advance(&mut self) -> Option<char> {
        if self.pos < self.chars.len() {
            let ch = self.chars[self.pos];
            self.pos += 1;
            if ch == '\n' {
                self.line += 1;
                self.col = 1;
            } else {
                self.col += 1;
            }
            Some(ch)
        } else {
            None
        }
    }

    fn skip_whitespace_and_comments(&mut self) {
        loop {
            // skip whitespace
            while self.pos < self.chars.len() && self.chars[self.pos].is_ascii_whitespace() {
                self.advance();
            }
            // skip -- line comments
            if self.pos + 1 < self.chars.len()
                && self.chars[self.pos] == '-'
                && self.chars[self.pos + 1] == '-'
            {
                while self.pos < self.chars.len() && self.chars[self.pos] != '\n' {
                    self.advance();
                }
            } else {
                break;
            }
        }
    }

    pub fn tokenize(&mut self) -> Vec<Token> {
        let mut tokens = Vec::new();
        loop {
            self.skip_whitespace_and_comments();
            if self.pos >= self.chars.len() {
                break;
            }
            if let Some(tok) = self.next_token() {
                tokens.push(tok);
            }
        }
        tokens.push(Token {
            token_type: TokenType::Eof,
            value: String::new(),
            line: self.line,
            col: self.col,
        });
        tokens
    }

    fn next_token(&mut self) -> Option<Token> {
        let l = self.line;
        let c = self.col;
        let ch = self.peek(0)?;

        match ch {
            '"' => Some(self.read_string(l, c)),
            '0'..='9' => Some(self.read_number(l, c)),
            ':' => Some(self.read_symbol_or_colon(l, c)),
            '-' => {
                if self.peek(1) == Some('>') {
                    self.advance();
                    self.advance();
                    Some(Token {
                        token_type: TokenType::Arrow,
                        value: "->".to_string(),
                        line: l,
                        col: c,
                    })
                } else {
                    self.advance();
                    Some(Token {
                        token_type: TokenType::Op,
                        value: "-".to_string(),
                        line: l,
                        col: c,
                    })
                }
            }
            '+' => {
                if self.peek(1) == Some('+') {
                    self.advance();
                    self.advance();
                    Some(Token {
                        token_type: TokenType::Op,
                        value: "++".to_string(),
                        line: l,
                        col: c,
                    })
                } else {
                    self.advance();
                    Some(Token {
                        token_type: TokenType::Op,
                        value: "+".to_string(),
                        line: l,
                        col: c,
                    })
                }
            }
            '*' => {
                self.advance();
                Some(Token {
                    token_type: TokenType::Op,
                    value: "*".to_string(),
                    line: l,
                    col: c,
                })
            }
            '/' => {
                self.advance();
                Some(Token {
                    token_type: TokenType::Op,
                    value: "/".to_string(),
                    line: l,
                    col: c,
                })
            }
            '=' => {
                if self.peek(1) == Some('=') {
                    self.advance();
                    self.advance();
                    Some(Token {
                        token_type: TokenType::Op,
                        value: "==".to_string(),
                        line: l,
                        col: c,
                    })
                } else if self.peek(1) == Some('>') {
                    self.advance();
                    self.advance();
                    Some(Token {
                        token_type: TokenType::FatArrow,
                        value: "=>".to_string(),
                        line: l,
                        col: c,
                    })
                } else {
                    self.advance();
                    Some(Token {
                        token_type: TokenType::Assign,
                        value: "=".to_string(),
                        line: l,
                        col: c,
                    })
                }
            }
            '!' => {
                if self.peek(1) == Some('=') {
                    self.advance();
                    self.advance();
                    Some(Token {
                        token_type: TokenType::Op,
                        value: "!=".to_string(),
                        line: l,
                        col: c,
                    })
                } else {
                    self.advance();
                    Some(Token {
                        token_type: TokenType::Bang,
                        value: "!".to_string(),
                        line: l,
                        col: c,
                    })
                }
            }
            '<' => {
                if self.peek(1) == Some('=') {
                    self.advance();
                    self.advance();
                    Some(Token {
                        token_type: TokenType::Op,
                        value: "<=".to_string(),
                        line: l,
                        col: c,
                    })
                } else {
                    self.advance();
                    Some(Token {
                        token_type: TokenType::Op,
                        value: "<".to_string(),
                        line: l,
                        col: c,
                    })
                }
            }
            '>' => {
                if self.peek(1) == Some('=') {
                    self.advance();
                    self.advance();
                    Some(Token {
                        token_type: TokenType::Op,
                        value: ">=".to_string(),
                        line: l,
                        col: c,
                    })
                } else {
                    self.advance();
                    Some(Token {
                        token_type: TokenType::Op,
                        value: ">".to_string(),
                        line: l,
                        col: c,
                    })
                }
            }
            '&' => {
                if self.peek(1) == Some('&') {
                    self.advance();
                    self.advance();
                    Some(Token {
                        token_type: TokenType::Op,
                        value: "&&".to_string(),
                        line: l,
                        col: c,
                    })
                } else {
                    self.advance();
                    Some(Token {
                        token_type: TokenType::Op,
                        value: "&".to_string(),
                        line: l,
                        col: c,
                    })
                }
            }
            '|' => {
                if self.peek(1) == Some('|') {
                    self.advance();
                    self.advance();
                    Some(Token {
                        token_type: TokenType::Op,
                        value: "||".to_string(),
                        line: l,
                        col: c,
                    })
                } else {
                    self.advance();
                    Some(Token {
                        token_type: TokenType::Pipe,
                        value: "|".to_string(),
                        line: l,
                        col: c,
                    })
                }
            }
            '{' => {
                self.advance();
                Some(Token {
                    token_type: TokenType::LBrace,
                    value: "{".to_string(),
                    line: l,
                    col: c,
                })
            }
            '}' => {
                self.advance();
                Some(Token {
                    token_type: TokenType::RBrace,
                    value: "}".to_string(),
                    line: l,
                    col: c,
                })
            }
            '(' => {
                self.advance();
                Some(Token {
                    token_type: TokenType::LParen,
                    value: "(".to_string(),
                    line: l,
                    col: c,
                })
            }
            ')' => {
                self.advance();
                Some(Token {
                    token_type: TokenType::RParen,
                    value: ")".to_string(),
                    line: l,
                    col: c,
                })
            }
            '[' => {
                self.advance();
                Some(Token {
                    token_type: TokenType::LBracket,
                    value: "[".to_string(),
                    line: l,
                    col: c,
                })
            }
            ']' => {
                self.advance();
                Some(Token {
                    token_type: TokenType::RBracket,
                    value: "]".to_string(),
                    line: l,
                    col: c,
                })
            }
            '.' => {
                if self.peek(1) == Some('.') {
                    self.advance();
                    self.advance();
                    Some(Token {
                        token_type: TokenType::DotDot,
                        value: "..".to_string(),
                        line: l,
                        col: c,
                    })
                } else {
                    self.advance();
                    Some(Token {
                        token_type: TokenType::Dot,
                        value: ".".to_string(),
                        line: l,
                        col: c,
                    })
                }
            }
            ',' => {
                self.advance();
                Some(Token {
                    token_type: TokenType::Comma,
                    value: ",".to_string(),
                    line: l,
                    col: c,
                })
            }
            '@' => {
                self.advance();
                Some(Token {
                    token_type: TokenType::At,
                    value: "@".to_string(),
                    line: l,
                    col: c,
                })
            }
            '?' => {
                self.advance();
                Some(Token {
                    token_type: TokenType::Question,
                    value: "?".to_string(),
                    line: l,
                    col: c,
                })
            }
            ch if ch.is_ascii_alphabetic() || ch == '_' => Some(self.read_ident_or_keyword(l, c)),
            _ => {
                self.advance();
                None
            }
        }
    }

    /// LAB-LANG-STRING-ESCAPES-P1: read a `"`-delimited string, decoding a minimal conventional escape
    /// set (`\"` `\\` `\n` `\t` `\r`). An invalid escape or an unterminated string returns an `Illegal`
    /// token whose `value` carries the reason — the parser surfaces it as a line-positioned diagnostic.
    /// Ordinary escape-free strings are unchanged (no `.ig` string literal in the tree contains a `\`).
    fn read_string(&mut self, l: usize, c: usize) -> Token {
        self.advance(); // consume opening "
        let mut buf = String::new();
        let illegal = |reason: &str| Token {
            token_type: TokenType::Illegal,
            value: reason.to_string(),
            line: l,
            col: c,
        };
        loop {
            match self.peek(0) {
                None => return illegal("unterminated string literal"),
                Some('"') => {
                    self.advance(); // consume closing "
                    return Token {
                        token_type: TokenType::StringLit,
                        value: buf,
                        line: l,
                        col: c,
                    };
                }
                Some('\\') => {
                    self.advance(); // consume the backslash
                    match self.peek(0) {
                        None => return illegal("unterminated string literal (trailing backslash)"),
                        Some(esc) => {
                            let decoded = match esc {
                                '"' => '"',
                                '\\' => '\\',
                                'n' => '\n',
                                't' => '\t',
                                'r' => '\r',
                                other => {
                                    return illegal(&format!("invalid string escape: \\{}", other))
                                }
                            };
                            self.advance(); // consume the escape char
                            buf.push(decoded);
                        }
                    }
                }
                Some(_) => buf.push(self.advance().unwrap()),
            }
        }
    }

    fn read_number(&mut self, l: usize, c: usize) -> Token {
        let mut buf = String::new();
        while let Some(ch) = self.peek(0) {
            if ch.is_ascii_digit() {
                buf.push(self.advance().unwrap());
            } else {
                break;
            }
        }
        if self.peek(0) == Some('.') {
            if let Some(next) = self.peek(1) {
                if next.is_ascii_digit() {
                    buf.push(self.advance().unwrap()); // consume '.'
                    while let Some(ch) = self.peek(0) {
                        if ch.is_ascii_digit() {
                            buf.push(self.advance().unwrap());
                        } else {
                            break;
                        }
                    }
                    return Token {
                        token_type: TokenType::FloatLit,
                        value: buf,
                        line: l,
                        col: c,
                    };
                }
            }
        }
        Token {
            token_type: TokenType::IntLit,
            value: buf,
            line: l,
            col: c,
        }
    }

    fn read_symbol_or_colon(&mut self, l: usize, c: usize) -> Token {
        self.advance(); // consume ':'
        if let Some(ch) = self.peek(0) {
            if ch.is_ascii_alphabetic() || ch == '_' {
                let mut buf = String::new();
                while let Some(ch) = self.peek(0) {
                    if ch.is_ascii_alphanumeric() || ch == '_' {
                        buf.push(self.advance().unwrap());
                    } else {
                        break;
                    }
                }
                return Token {
                    token_type: TokenType::SymbolLit,
                    value: buf,
                    line: l,
                    col: c,
                };
            }
        }
        Token {
            token_type: TokenType::Colon,
            value: ":".to_string(),
            line: l,
            col: c,
        }
    }

    fn read_ident_or_keyword(&mut self, l: usize, c: usize) -> Token {
        let mut buf = String::new();
        while let Some(ch) = self.peek(0) {
            if ch == '.' {
                if let Some(next) = self.peek(1) {
                    if next.is_ascii_uppercase()
                        || (buf.starts_with("stdlib.IO") && next.is_ascii_lowercase())
                    {
                        buf.push(self.advance().unwrap()); // consume '.'
                        continue;
                    }
                }
                break;
            }
            if ch.is_ascii_alphanumeric() || ch == '_' {
                buf.push(self.advance().unwrap());
            } else {
                break;
            }
        }
        let t_type = if KEYWORDS.contains(&buf.as_str()) {
            if buf == "true" || buf == "false" {
                TokenType::BoolLit
            } else if buf == "nil" {
                TokenType::NilLit
            } else {
                TokenType::Keyword
            }
        } else {
            TokenType::Ident
        };
        Token {
            token_type: t_type,
            value: buf,
            line: l,
            col: c,
        }
    }
}
