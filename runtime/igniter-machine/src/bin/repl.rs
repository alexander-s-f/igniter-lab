// Igniter Machine — Terminal UI REPL
// Ratatui 0.26 + crossterm 0.27
#![allow(unused_imports)]

use std::io::{self, Stdout};
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use crossterm::{
    event::{
        self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyEventKind, KeyModifiers,
    },
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    backend::CrosstermBackend,
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span, Text},
    widgets::{Block, Borders, List, ListItem, Paragraph, Wrap},
    Frame, Terminal,
};

use igniter_machine::{fact::Fact, machine::IgniterMachine};

// ─── OutputLine ─────────────────────────────────────────────────────────────

#[derive(Clone)]
enum OutputLine {
    Command(String),
    Success(String),
    Error(String),
    Info(String),
    Json(String),
    Separator,
}

impl OutputLine {
    fn to_line(&self) -> Line<'static> {
        match self {
            OutputLine::Command(s) => Line::from(vec![Span::styled(
                format!("> {}", s),
                Style::default().fg(Color::DarkGray),
            )]),
            OutputLine::Success(s) => Line::from(vec![Span::styled(
                format!("✔ {}", s),
                Style::default().fg(Color::Green),
            )]),
            OutputLine::Error(s) => Line::from(vec![Span::styled(
                format!("✗ {}", s),
                Style::default().fg(Color::Red),
            )]),
            OutputLine::Info(s) => Line::from(vec![Span::styled(
                format!("  {}", s),
                Style::default().fg(Color::Cyan),
            )]),
            OutputLine::Json(s) => Line::from(vec![Span::styled(
                s.clone(),
                Style::default().fg(Color::Yellow),
            )]),
            OutputLine::Separator => Line::from(vec![Span::styled(
                "────────────────────────────────────────────────────────────────",
                Style::default()
                    .fg(Color::DarkGray)
                    .add_modifier(Modifier::DIM),
            )]),
        }
    }
}

// ─── App ────────────────────────────────────────────────────────────────────

struct App {
    machine: IgniterMachine,
    backend_label: String,
    input: String,
    history: Vec<OutputLine>,
    cmd_history: Vec<String>,
    cmd_history_pos: Option<usize>,
    scroll_offset: usize,
    facts_count: usize,
    should_quit: bool,
}

impl App {
    fn new(machine: IgniterMachine, backend_label: String) -> Self {
        let mut app = Self {
            machine,
            backend_label,
            input: String::new(),
            history: Vec::new(),
            cmd_history: Vec::new(),
            cmd_history_pos: None,
            scroll_offset: 0,
            facts_count: 0,
            should_quit: false,
        };
        app.push_welcome();
        app
    }

    fn push_welcome(&mut self) {
        self.history.push(OutputLine::Info(
            "╔═══════════════════════════════════╗".into(),
        ));
        self.history.push(OutputLine::Info(
            "║   Igniter Machine  v0.1.0         ║".into(),
        ));
        self.history.push(OutputLine::Info(
            "║   Smalltalk-style live workspace  ║".into(),
        ));
        self.history.push(OutputLine::Info(
            "╚═══════════════════════════════════╝".into(),
        ));
        self.history.push(OutputLine::Info(String::new()));
        self.history.push(OutputLine::Info(
            "Type 'help' for commands.  Ctrl+C to quit.".into(),
        ));
    }

    fn push_output(&mut self, line: OutputLine) {
        self.history.push(line);
        self.scroll_to_bottom();
    }

    fn scroll_to_bottom(&mut self) {
        self.scroll_offset = self.history.len().saturating_sub(1);
    }

    fn scroll_up(&mut self, n: usize) {
        self.scroll_offset = self.scroll_offset.saturating_sub(n);
    }

    fn scroll_down(&mut self, n: usize) {
        let max = self.history.len().saturating_sub(1);
        self.scroll_offset = (self.scroll_offset + n).min(max);
    }

    fn contracts_list(&self) -> Vec<String> {
        self.machine
            .registry
            .read()
            .contracts
            .keys()
            .cloned()
            .collect::<Vec<_>>()
    }

    fn contract_fragment_class(&self, name: &str) -> String {
        let reg = self.machine.registry.read();
        if let Some(contract) = reg.contracts.get(name) {
            if let Some(cls) = contract
                .get("fragment_class")
                .or_else(|| contract.get("modifier"))
                .and_then(|v| v.as_str())
            {
                return cls.to_string();
            }
        }
        "unknown".to_string()
    }

    fn refresh_facts_count(&mut self) {
        let count = futures::executor::block_on(self.machine.storage.all_facts())
            .map(|v| v.len())
            .unwrap_or(0);
        self.facts_count = count;
    }

    // ── Command dispatch ──────────────────────────────────────────────────

    fn execute_command(&mut self, raw: String) {
        let trimmed = raw.trim().to_string();
        if trimmed.is_empty() {
            return;
        }

        // Save to command history
        if self.cmd_history.last().map(|s| s.as_str()) != Some(&trimmed) {
            self.cmd_history.push(trimmed.clone());
        }
        self.cmd_history_pos = None;

        self.push_output(OutputLine::Command(trimmed.clone()));

        let parts: Vec<&str> = trimmed.splitn(4, ' ').collect();
        let cmd = parts[0];

        match cmd {
            "help" => self.cmd_help(),
            "load" => {
                let path_str = parts.get(1).copied().unwrap_or("");
                let name_override = parts.get(2).copied().map(|s| s.to_string());
                self.cmd_load(path_str, name_override);
            }
            "dispatch" => {
                let name = parts.get(1).copied().unwrap_or("");
                // Gather remaining args as JSON (may be split by splitn above)
                let json_str = trimmed.splitn(3, ' ').nth(2).unwrap_or("{}").trim();
                self.cmd_dispatch(name, json_str);
            }
            "facts" => {
                let store = parts.get(1).copied().unwrap_or("");
                let key = parts.get(2).copied();
                let as_of_str = parts.get(3).copied();
                self.cmd_facts(store, key, as_of_str);
            }
            "write" => {
                let store = parts.get(1).copied().unwrap_or("");
                let key = parts.get(2).copied().unwrap_or("");
                let json_str = trimmed.splitn(4, ' ').nth(3).unwrap_or("{}").trim();
                self.cmd_write(store, key, json_str);
            }
            "history" => {
                let store = parts.get(1).copied().unwrap_or("");
                let key = parts.get(2).copied().unwrap_or("");
                self.cmd_history_facts(store, key);
            }
            "contracts" => self.cmd_contracts(),
            "observations" => self.cmd_observations(),
            "checkpoint" => {
                let path = parts.get(1).copied().unwrap_or("machine.igm");
                self.cmd_checkpoint(path);
            }
            "resume" => {
                let path = parts.get(1).copied().unwrap_or("");
                self.cmd_resume(path);
            }
            "clear" => {
                self.history.clear();
                self.scroll_offset = 0;
            }
            "backend" => {
                let spec = parts.get(1).copied().unwrap_or("");
                self.cmd_backend(spec);
            }
            "quit" | "exit" => {
                self.should_quit = true;
            }
            other => {
                self.push_output(OutputLine::Error(format!(
                    "Unknown command: '{}'. Type 'help' for a list.",
                    other
                )));
            }
        }

        self.refresh_facts_count();
    }

    fn cmd_help(&mut self) {
        let lines = vec![
            ("help", "", "Show this help message"),
            (
                "load",
                "<path.ig> [Name]",
                "Load & compile a contract source file",
            ),
            (
                "dispatch",
                "<Name> [json]",
                "Execute a contract with JSON inputs",
            ),
            (
                "facts",
                "<store> [key] [as_of:<ts>]",
                "Query facts from storage",
            ),
            ("write", "<store> <key> <json>", "Write a fact into storage"),
            (
                "history",
                "<store> <key>",
                "Show temporal history for a key",
            ),
            ("contracts", "", "List all loaded contracts"),
            ("observations", "", "Show VM observation log"),
            ("checkpoint", "<path>", "Save machine state to .igm file"),
            ("resume", "<path>", "Restore machine from .igm file"),
            (
                "backend",
                "<in_memory|rocksdb:<p>|remote_tcp:<addr>>",
                "Switch backend",
            ),
            ("clear", "", "Clear output history"),
            ("quit / exit", "", "Exit the REPL"),
        ];
        self.push_output(OutputLine::Info("Available commands:".into()));
        self.push_output(OutputLine::Separator);
        for (cmd, args, desc) in lines {
            let line = if args.is_empty() {
                format!("  {:>12}  {}", cmd, desc)
            } else {
                format!("  {:>12}  {}  —  {}", cmd, args, desc)
            };
            self.push_output(OutputLine::Info(line));
        }
        self.push_output(OutputLine::Info(String::new()));
        self.push_output(OutputLine::Info(
            "Keyboard: ↑↓ history  PgUp/PgDn scroll  Ctrl+L clear  Tab autocomplete".into(),
        ));
    }

    fn cmd_load(&mut self, path_str: &str, name_override: Option<String>) {
        if path_str.is_empty() {
            self.push_output(OutputLine::Error(
                "Usage: load <path.ig> [ContractName]".into(),
            ));
            return;
        }

        let contract_name = name_override.unwrap_or_else(|| {
            Path::new(path_str)
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("contract")
                .to_string()
        });

        match std::fs::read_to_string(path_str) {
            Err(e) => {
                self.push_output(OutputLine::Error(format!(
                    "Failed to read '{}': {}",
                    path_str, e
                )));
            }
            Ok(source) => match self.machine.load_contract_source(&source, &contract_name) {
                Ok(_) => {
                    self.push_output(OutputLine::Success(format!(
                        "Loaded contract '{}' from {}",
                        contract_name, path_str
                    )));
                }
                Err(e) => {
                    self.push_output(OutputLine::Error(format!("Compilation error: {}", e)));
                }
            },
        }
    }

    fn cmd_dispatch(&mut self, name: &str, json_str: &str) {
        if name.is_empty() {
            self.push_output(OutputLine::Error(
                "Usage: dispatch <ContractName> [json]".into(),
            ));
            return;
        }

        let inputs: serde_json::Value =
            serde_json::from_str(json_str).unwrap_or(serde_json::json!({}));

        match futures::executor::block_on(self.machine.dispatch(name, inputs)) {
            Ok(result) => {
                self.push_output(OutputLine::Success(format!("dispatch '{}' →", name)));
                for line in format_json(&result).lines() {
                    self.push_output(OutputLine::Json(format!("  {}", line)));
                }
            }
            Err(e) => {
                self.push_output(OutputLine::Error(format!("{}", e)));
            }
        }
    }

    fn cmd_facts(&mut self, store: &str, key: Option<&str>, as_of_str: Option<&str>) {
        if store.is_empty() {
            self.push_output(OutputLine::Error(
                "Usage: facts <store> [key] [as_of:<ts>]".into(),
            ));
            return;
        }

        let as_of: Option<f64> = as_of_str.and_then(|s| {
            let stripped = s.strip_prefix("as_of:").unwrap_or(s);
            stripped.parse::<f64>().ok()
        });

        let key_str = key.unwrap_or("");
        if key_str.is_empty() {
            // All facts in store — use all_facts filtered
            match futures::executor::block_on(self.machine.storage.all_facts()) {
                Err(e) => {
                    self.push_output(OutputLine::Error(format!("{}", e)));
                    return;
                }
                Ok(facts) => {
                    let filtered: Vec<_> = facts.iter().filter(|f| f.store == store).collect();
                    if filtered.is_empty() {
                        self.push_output(OutputLine::Info(format!(
                            "No facts in store '{}'",
                            store
                        )));
                    } else {
                        self.push_output(OutputLine::Info(format!(
                            "{} fact(s) in store '{}':",
                            filtered.len(),
                            store
                        )));
                        for f in filtered {
                            render_fact_summary(f, &mut self.history);
                        }
                    }
                }
            }
        } else {
            match futures::executor::block_on(
                self.machine.storage.facts_for(store, key_str, None, as_of),
            ) {
                Err(e) => {
                    self.push_output(OutputLine::Error(format!("{}", e)));
                }
                Ok(facts) => {
                    if facts.is_empty() {
                        self.push_output(OutputLine::Info(format!(
                            "No facts for '{}/{}'{}",
                            store,
                            key_str,
                            as_of.map(|t| format!(" as_of {}", t)).unwrap_or_default()
                        )));
                    } else {
                        for f in &facts {
                            render_fact_summary(f, &mut self.history);
                        }
                    }
                }
            }
        }
    }

    fn cmd_write(&mut self, store: &str, key: &str, json_str: &str) {
        if store.is_empty() || key.is_empty() {
            self.push_output(OutputLine::Error(
                "Usage: write <store> <key> <json>".into(),
            ));
            return;
        }

        let value: serde_json::Value =
            serde_json::from_str(json_str).unwrap_or(serde_json::json!({}));

        let value_hash = blake3::hash(json_str.as_bytes()).to_hex().to_string();
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs_f64())
            .unwrap_or(0.0);

        let fact = Fact {
            id: uuid::Uuid::new_v4().to_string(),
            store: store.to_string(),
            key: key.to_string(),
            value,
            value_hash,
            causation: None,
            transaction_time: now,
            valid_time: Some(now),
            schema_version: 1,
            producer: None,
            derivation: None,
        };

        match futures::executor::block_on(self.machine.write_fact(fact)) {
            Ok(_) => {
                self.push_output(OutputLine::Success(format!(
                    "Wrote fact to '{}/{}'",
                    store, key
                )));
            }
            Err(e) => {
                self.push_output(OutputLine::Error(format!("{}", e)));
            }
        }
    }

    fn cmd_history_facts(&mut self, store: &str, key: &str) {
        if store.is_empty() || key.is_empty() {
            self.push_output(OutputLine::Error("Usage: history <store> <key>".into()));
            return;
        }

        match futures::executor::block_on(self.machine.storage.facts_for(store, key, None, None)) {
            Err(e) => {
                self.push_output(OutputLine::Error(format!("{}", e)));
            }
            Ok(mut facts) => {
                if facts.is_empty() {
                    self.push_output(OutputLine::Info(format!(
                        "No history for '{}/{}'",
                        store, key
                    )));
                    return;
                }
                facts.sort_by(|a, b| {
                    a.transaction_time
                        .partial_cmp(&b.transaction_time)
                        .unwrap_or(std::cmp::Ordering::Equal)
                });
                self.push_output(OutputLine::Info(format!(
                    "Temporal history for '{}/{}' ({} entries):",
                    store,
                    key,
                    facts.len()
                )));
                self.push_output(OutputLine::Separator);
                for (i, f) in facts.iter().enumerate() {
                    self.push_output(OutputLine::Info(format!(
                        "[{}] tx:{:.3}  vt:{}  hash:{}...",
                        i,
                        f.transaction_time,
                        f.valid_time
                            .map(|t| format!("{:.3}", t))
                            .unwrap_or("—".into()),
                        &f.value_hash[..8.min(f.value_hash.len())]
                    )));
                    for line in format_json(&f.value).lines() {
                        self.push_output(OutputLine::Json(format!("       {}", line)));
                    }
                }
            }
        }
    }

    fn cmd_contracts(&mut self) {
        let names = self.contracts_list();
        if names.is_empty() {
            self.push_output(OutputLine::Info("No contracts loaded.".into()));
        } else {
            self.push_output(OutputLine::Info(format!("{} contract(s):", names.len())));
            self.push_output(OutputLine::Separator);
            let mut sorted = names;
            sorted.sort();
            for name in &sorted {
                let cls = self.contract_fragment_class(name);
                self.push_output(OutputLine::Info(format!("  ● {}  [{}]", name, cls)));
            }
        }
    }

    fn cmd_observations(&mut self) {
        let obs = self.machine.observations.read().clone();
        if obs.is_empty() {
            self.push_output(OutputLine::Info("No observations recorded.".into()));
        } else {
            self.push_output(OutputLine::Info(format!("{} observation(s):", obs.len())));
            self.push_output(OutputLine::Separator);
            for o in &obs {
                self.push_output(OutputLine::Info(format!(
                    "  [{}] kind={} ts={:.3}",
                    o.id, o.kind, o.timestamp
                )));
                for line in format_json(&o.value).lines() {
                    self.push_output(OutputLine::Json(format!("    {}", line)));
                }
            }
        }
    }

    fn cmd_checkpoint(&mut self, path: &str) {
        // checkpoint/resume are async on IgniterMachine; drive them with the same synchronous executor the
        // REPL already uses for dispatch/all_facts/write_fact (no Tokio in this TUI binary).
        match futures::executor::block_on(self.machine.checkpoint(Path::new(path))) {
            Ok(_) => {
                self.push_output(OutputLine::Success(format!(
                    "Checkpoint saved to '{}'",
                    path
                )));
            }
            Err(e) => {
                self.push_output(OutputLine::Error(format!("{}", e)));
            }
        }
    }

    fn cmd_resume(&mut self, path: &str) {
        if path.is_empty() {
            self.push_output(OutputLine::Error("Usage: resume <path.igm>".into()));
            return;
        }
        match futures::executor::block_on(IgniterMachine::resume(
            Path::new(path),
            None,
            "in_memory",
        )) {
            Ok(new_machine) => {
                self.machine = new_machine;
                self.backend_label = "in_memory".to_string();
                self.refresh_facts_count();
                self.push_output(OutputLine::Success(format!(
                    "Resumed machine from '{}'",
                    path
                )));
            }
            Err(e) => {
                self.push_output(OutputLine::Error(format!("{}", e)));
            }
        }
    }

    fn cmd_backend(&mut self, spec: &str) {
        if spec.is_empty() {
            self.push_output(OutputLine::Error(
                "Usage: backend <in_memory|rocksdb:<path>|remote_tcp:<addr>>".into(),
            ));
            return;
        }
        let (backend_type, data_dir) = if spec.starts_with("rocksdb:") {
            let path_str = spec.trim_start_matches("rocksdb:");
            ("rocksdb".to_string(), Some(PathBuf::from(path_str)))
        } else {
            (spec.to_string(), None)
        };

        match IgniterMachine::new(data_dir, &backend_type) {
            Ok(new_machine) => {
                self.machine = new_machine;
                self.backend_label = spec.to_string();
                self.facts_count = 0;
                self.push_output(OutputLine::Success(format!(
                    "Switched to backend: {}",
                    spec
                )));
            }
            Err(e) => {
                self.push_output(OutputLine::Error(format!("{}", e)));
            }
        }
    }

    // ── Tab autocomplete (contract names for dispatch) ────────────────────

    fn try_autocomplete(&mut self) {
        let parts: Vec<&str> = self.input.splitn(3, ' ').collect();
        if parts.len() == 2 && parts[0] == "dispatch" {
            let prefix = parts[1];
            let names = self.contracts_list();
            let matches: Vec<_> = names.iter().filter(|n| n.starts_with(prefix)).collect();
            match matches.len() {
                0 => {}
                1 => {
                    self.input = format!("dispatch {}", matches[0]);
                }
                _ => {
                    let list = matches
                        .iter()
                        .map(|s| s.as_str())
                        .collect::<Vec<_>>()
                        .join("  ");
                    self.push_output(OutputLine::Info(format!("  {}", list)));
                }
            }
        }
    }
}

// ─── Helpers ────────────────────────────────────────────────────────────────

fn format_json(val: &serde_json::Value) -> String {
    serde_json::to_string_pretty(val).unwrap_or_else(|_| val.to_string())
}

fn fragment_color(class: &str) -> Color {
    match class {
        "core" => Color::Green,
        "escape" => Color::Yellow,
        "temporal" => Color::Cyan,
        "oof" => Color::Red,
        _ => Color::Gray,
    }
}

fn render_fact_summary(f: &Fact, history: &mut Vec<OutputLine>) {
    history.push(OutputLine::Info(format!(
        "  key={} store={} tx={:.3} vt={}",
        f.key,
        f.store,
        f.transaction_time,
        f.valid_time
            .map(|t| format!("{:.3}", t))
            .unwrap_or("—".into()),
    )));
    for line in format_json(&f.value).lines() {
        history.push(OutputLine::Json(format!("    {}", line)));
    }
}

// ─── Render ─────────────────────────────────────────────────────────────────

fn render_ui(frame: &mut Frame, app: &App) {
    let size = frame.size();

    // Top-level split: status bar (1 row), body, input bar (3 rows)
    let root_chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(1),
            Constraint::Min(0),
            Constraint::Length(3),
        ])
        .split(size);

    render_status_bar(frame, app, root_chunks[0]);
    render_body(frame, app, root_chunks[1]);
    render_input_bar(frame, app, root_chunks[2]);
}

fn render_status_bar(frame: &mut Frame, app: &App, area: Rect) {
    let contracts_count = app.machine.registry.read().contracts.len();
    let now = chrono::Local::now().format("%H:%M:%S").to_string();

    let title = Span::styled(
        " Igniter Machine ",
        Style::default()
            .fg(Color::White)
            .bg(Color::Blue)
            .add_modifier(Modifier::BOLD),
    );
    let separator = Span::styled("─", Style::default().fg(Color::White).bg(Color::Blue));
    let info = Span::styled(
        format!(
            "  backend: {}  ·  facts: {}  ·  contracts: {}  ·  {}  ",
            app.backend_label, app.facts_count, contracts_count, now
        ),
        Style::default()
            .fg(Color::White)
            .bg(Color::Blue)
            .add_modifier(Modifier::BOLD),
    );

    // Fill the rest of the line with the same background
    let fill_len = area.width as usize;
    let content_len = 18 + info.content.len();
    let padding = " ".repeat(fill_len.saturating_sub(content_len));
    let pad = Span::styled(padding, Style::default().fg(Color::White).bg(Color::Blue));

    let bar = Paragraph::new(Line::from(vec![title, separator, info, pad]));
    frame.render_widget(bar, area);
}

fn render_body(frame: &mut Frame, app: &App, area: Rect) {
    let chunks = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(25), Constraint::Percentage(75)])
        .split(area);

    render_contracts_panel(frame, app, chunks[0]);
    render_output_panel(frame, app, chunks[1]);
}

fn render_contracts_panel(frame: &mut Frame, app: &App, area: Rect) {
    let block = Block::default()
        .title(" CONTRACTS ")
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::DarkGray));

    let names = {
        let reg = app.machine.registry.read();
        let mut v: Vec<String> = reg.contracts.keys().cloned().collect();
        v.sort();
        v
    };

    let items: Vec<ListItem> = if names.is_empty() {
        vec![ListItem::new(Line::from(vec![Span::styled(
            "  (empty)",
            Style::default().fg(Color::DarkGray),
        )]))]
    } else {
        names
            .iter()
            .map(|name| {
                let cls = {
                    let reg = app.machine.registry.read();
                    reg.contracts
                        .get(name)
                        .and_then(|c| {
                            c.get("fragment_class")
                                .or_else(|| c.get("modifier"))
                                .and_then(|v| v.as_str())
                        })
                        .unwrap_or("unknown")
                        .to_string()
                };
                let color = fragment_color(&cls);
                let line = Line::from(vec![
                    Span::styled("● ", Style::default().fg(color)),
                    Span::styled(name.clone(), Style::default().fg(Color::White)),
                    Span::styled(
                        format!(" [{}]", cls),
                        Style::default().fg(color).add_modifier(Modifier::DIM),
                    ),
                ]);
                ListItem::new(line)
            })
            .collect()
    };

    let list = List::new(items).block(block);
    frame.render_widget(list, area);
}

fn render_output_panel(frame: &mut Frame, app: &App, area: Rect) {
    let block = Block::default()
        .title(" OUTPUT ")
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::DarkGray));

    let inner_height = area.height.saturating_sub(2) as usize;

    // Compute which lines to display
    let total = app.history.len();
    let start = if total > inner_height {
        let max_start = total - inner_height;
        app.scroll_offset.min(max_start)
    } else {
        0
    };
    let end = (start + inner_height).min(total);

    let lines: Vec<Line> = app.history[start..end]
        .iter()
        .map(|ol| ol.to_line())
        .collect();

    let text = Text::from(lines);
    let para = Paragraph::new(text).block(block);
    frame.render_widget(para, area);
}

fn render_input_bar(frame: &mut Frame, app: &App, area: Rect) {
    let block = Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::Blue));

    let prompt = Span::styled(
        ">> ",
        Style::default()
            .fg(Color::Blue)
            .add_modifier(Modifier::BOLD),
    );
    let text = Span::styled(app.input.clone(), Style::default().fg(Color::White));
    let cursor = Span::styled(
        "_",
        Style::default()
            .fg(Color::White)
            .add_modifier(Modifier::RAPID_BLINK),
    );

    let line = Line::from(vec![prompt, text, cursor]);
    let para = Paragraph::new(line).block(block);
    frame.render_widget(para, area);
}

// ─── Headless script runner (P20) ─────────────────────────────────────────────

/// Run a file of REPL commands through the same dispatch path the TUI uses.
fn run_script(mut app: App, script_path: &Path) -> i32 {
    let content = match std::fs::read_to_string(script_path) {
        Ok(c) => c,
        Err(e) => {
            eprintln!(
                "igniter-repl --script: cannot read {}: {}",
                script_path.display(),
                e
            );
            return 1;
        }
    };

    // Everything already in history is the welcome banner; only judge command output produced below.
    let baseline = app.history.len();
    for raw in content.lines() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        app.execute_command(line.to_string());
    }

    let mut had_error = false;
    for ol in &app.history[baseline..] {
        match ol {
            OutputLine::Command(s) => println!("> {}", s),
            OutputLine::Success(s) => println!("OK {}", s),
            OutputLine::Error(s) => {
                had_error = true;
                println!("ERROR {}", s);
            }
            OutputLine::Info(s) => println!("{}", s),
            OutputLine::Json(s) => println!("{}", s),
            OutputLine::Separator => {}
        }
    }

    if had_error {
        println!("igniter-repl: SCRIPT FAILED");
        1
    } else {
        println!("igniter-repl: SCRIPT OK");
        0
    }
}

// ─── Main ────────────────────────────────────────────────────────────────────

fn main() {
    let args: Vec<String> = std::env::args().collect();

    let mut backend_type = "in_memory".to_string();
    let mut data_dir: Option<PathBuf> = None;
    let mut resume_path: Option<PathBuf> = None;
    let mut script_path: Option<PathBuf> = None;

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--script" => {
                if i + 1 < args.len() {
                    script_path = Some(PathBuf::from(&args[i + 1]));
                    i += 2;
                } else {
                    eprintln!("--script requires a path to a command file");
                    std::process::exit(1);
                }
            }
            "--backend" => {
                if i + 1 < args.len() {
                    backend_type = args[i + 1].clone();
                    i += 2;
                } else {
                    eprintln!("--backend requires a value");
                    std::process::exit(1);
                }
            }
            "--data-dir" => {
                if i + 1 < args.len() {
                    data_dir = Some(PathBuf::from(&args[i + 1]));
                    i += 2;
                } else {
                    eprintln!("--data-dir requires a value");
                    std::process::exit(1);
                }
            }
            "--resume" => {
                if i + 1 < args.len() {
                    resume_path = Some(PathBuf::from(&args[i + 1]));
                    i += 2;
                } else {
                    eprintln!("--resume requires a value");
                    std::process::exit(1);
                }
            }
            other => {
                eprintln!("Unknown argument: {}", other);
                std::process::exit(1);
            }
        }
    }

    // Build or resume machine
    let machine = if let Some(ref rpath) = resume_path {
        match futures::executor::block_on(IgniterMachine::resume(rpath, data_dir, &backend_type)) {
            Ok(m) => m,
            Err(e) => {
                eprintln!("Failed to resume machine: {}", e);
                std::process::exit(1);
            }
        }
    } else {
        match IgniterMachine::new(data_dir, &backend_type) {
            Ok(m) => m,
            Err(e) => {
                eprintln!("Failed to create machine: {}", e);
                std::process::exit(1);
            }
        }
    };

    let backend_label = if let Some(ref rpath) = resume_path {
        format!("{} (resumed {})", backend_type, rpath.display())
    } else {
        backend_type.clone()
    };

    // Script mode exits before terminal setup, so no raw mode or alternate screen is entered.
    if let Some(ref spath) = script_path {
        let app = App::new(machine, backend_label);
        std::process::exit(run_script(app, spath));
    }

    // Setup terminal panic hook for graceful restore
    let original_hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        let _ = disable_raw_mode();
        let mut stdout = io::stdout();
        let _ = execute!(stdout, LeaveAlternateScreen, DisableMouseCapture);
        original_hook(info);
    }));

    // Setup terminal
    let mut stdout = io::stdout();
    if let Err(e) = enable_raw_mode() {
        eprintln!("Failed to enable raw mode: {}", e);
        std::process::exit(1);
    }
    if let Err(e) = execute!(stdout, EnterAlternateScreen, EnableMouseCapture) {
        eprintln!("Failed to enter alternate screen: {}", e);
        let _ = disable_raw_mode();
        std::process::exit(1);
    }

    let backend = CrosstermBackend::new(io::stdout());
    let mut terminal = match Terminal::new(backend) {
        Ok(t) => t,
        Err(e) => {
            eprintln!("Failed to create terminal: {}", e);
            let _ = disable_raw_mode();
            let _ = execute!(io::stdout(), LeaveAlternateScreen, DisableMouseCapture);
            std::process::exit(1);
        }
    };

    let mut app = App::new(machine, backend_label);

    // Initial facts count
    app.refresh_facts_count();

    // Event loop
    let tick_rate = Duration::from_millis(200);
    let mut last_tick = Instant::now();

    loop {
        if let Err(e) = terminal.draw(|f| render_ui(f, &app)) {
            eprintln!("Draw error: {}", e);
            break;
        }

        let timeout = tick_rate
            .checked_sub(last_tick.elapsed())
            .unwrap_or(Duration::ZERO);

        if event::poll(timeout).unwrap_or(false) {
            if let Ok(evt) = event::read() {
                match evt {
                    Event::Key(key) if key.kind == KeyEventKind::Press => {
                        match key.code {
                            // Quit
                            KeyCode::Char('c') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                                app.should_quit = true;
                            }
                            KeyCode::Esc => {
                                app.should_quit = true;
                            }

                            // Clear screen
                            KeyCode::Char('l') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                                app.history.clear();
                                app.scroll_offset = 0;
                            }

                            // Execute command
                            KeyCode::Enter => {
                                let cmd = app.input.drain(..).collect::<String>();
                                app.execute_command(cmd);
                            }

                            // Backspace
                            KeyCode::Backspace => {
                                app.input.pop();
                                app.cmd_history_pos = None;
                            }

                            // Command history navigation
                            KeyCode::Up => {
                                if !app.cmd_history.is_empty() {
                                    let new_pos = match app.cmd_history_pos {
                                        None => app.cmd_history.len() - 1,
                                        Some(p) => p.saturating_sub(1),
                                    };
                                    app.cmd_history_pos = Some(new_pos);
                                    app.input = app.cmd_history[new_pos].clone();
                                }
                            }
                            KeyCode::Down => match app.cmd_history_pos {
                                None => {}
                                Some(p) => {
                                    if p + 1 < app.cmd_history.len() {
                                        let new_pos = p + 1;
                                        app.cmd_history_pos = Some(new_pos);
                                        app.input = app.cmd_history[new_pos].clone();
                                    } else {
                                        app.cmd_history_pos = None;
                                        app.input.clear();
                                    }
                                }
                            },

                            // Scroll output
                            KeyCode::PageUp => {
                                app.scroll_up(10);
                            }
                            KeyCode::PageDown => {
                                app.scroll_down(10);
                            }

                            // Tab autocomplete
                            KeyCode::Tab => {
                                app.try_autocomplete();
                            }

                            // Regular character input
                            KeyCode::Char(c) => {
                                app.input.push(c);
                                app.cmd_history_pos = None;
                            }

                            _ => {}
                        }
                    }
                    _ => {}
                }
            }
        }

        if last_tick.elapsed() >= tick_rate {
            last_tick = Instant::now();
        }

        if app.should_quit {
            break;
        }
    }

    // Restore terminal
    let _ = disable_raw_mode();
    let _ = execute!(
        terminal.backend_mut(),
        LeaveAlternateScreen,
        DisableMouseCapture
    );
    let _ = terminal.show_cursor();
}
