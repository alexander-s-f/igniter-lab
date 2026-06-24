use crate::compiler::Compiler;
use crate::tbackend::{MemoryHistoryBackend, TBackend};
use crate::value::Value;
use crate::vm::{FunctionEntry, VM};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value as JsonValue};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Arc;
use std::time::Instant;

const TWO_PI: f64 = std::f64::consts::PI * 2.0;
const MODE_ALL_TO_ALL_TICK: &str = "all_to_all_tick";
const MODE_NODE_TICK: &str = "node_tick";
const INIT_UNIFORM_SPREAD: &str = "uniform_spread";
const INIT_SHUFFLED_UNIFORM_SPREAD: &str = "shuffled_uniform_spread";
const INIT_LOCALIZED_CHIMERA_SEED: &str = "localized_chimera_seed";
const TOPO_NONLOCAL_RING: &str = "nonlocal_ring";
const GOLDEN_RATIO_FRAC: f64 = 0.6180339887498949;
const OMEGA_LORENTZIAN_QUANTILE_GRID: &str = "lorentzian_quantile_grid";
const OMEGA_SHUFFLED_LORENTZIAN_QUANTILE_GRID: &str = "shuffled_lorentzian_quantile_grid";
const WEIGHT_POLICY_TOPOLOGY_DEFAULT: &str = "topology_default";
const WEIGHT_POLICY_DEGREE_NORMALIZED: &str = "degree_normalized";

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct KuramotoConfig {
    #[serde(default = "default_kernel_mode")]
    pub kernel_mode: String,
    pub seed: u64,
    pub gamma: f64,
    pub kc_expected: f64,
    pub n_values: Vec<usize>,
    pub k_values: Vec<f64>,
    pub dt: f64,
    pub ticks: usize,
    pub plateau_window: usize,
    pub omega_clip: f64,
    #[serde(default = "default_series_stride")]
    pub series_sample_stride: usize,
    #[serde(default = "default_cli_sample_ticks")]
    pub cli_sample_ticks: usize,
    #[serde(default = "default_topologies")]
    pub topologies: Vec<String>,
    #[serde(default = "default_init_phase_mode")]
    pub init_phase_mode: String,
    #[serde(default = "default_omega_assignment")]
    pub omega_assignment: String,
    #[serde(default)]
    pub topology_relabel_seed: Option<u64>,
    #[serde(default = "default_weight_policy")]
    pub weight_policy: String,
    // Kuramoto-Sakaguchi phase lag (chimera). When Some, the per-node kernel receives an `alpha`
    // input and coupling is sin(theta_j - theta_i - alpha). None = legacy plain node_tick (no alpha).
    #[serde(default)]
    pub phase_lag_alpha: Option<f64>,
    // Nonlocal-ring coupling radius R (each node couples to its R nearest neighbours on each side,
    // weight 1/(2R)). Required when a topology is "nonlocal_ring".
    #[serde(default)]
    pub coupling_radius: Option<usize>,
    // Localized chimera seed: fraction of the ring (centred) initialised incoherent; rest coherent.
    #[serde(default)]
    pub incoherent_fraction: Option<f64>,
    // Emit per-node spatial_profile.csv (Z_i) + omega_profile.csv (Omega_i). Default off keeps prior
    // node_tick bundles byte-identical.
    #[serde(default)]
    pub emit_spatial_profiles: bool,
    // EMERGENCE-STAGE2-ABLATION-MAP-P16: deterministic knockout intervention. When Some(k), oscillator k is
    // removed from the dynamics (every other node's neighbour list drops edges to k → k exerts no coupling)
    // AND excluded from the global order-parameter measurement. Everything else is byte-identical, so the
    // macro delta vs the baseline is the EXACT causal contribution of element k, with zero confound. node_tick
    // only. Default None keeps prior bundles byte-identical.
    #[serde(default)]
    pub ablate_node: Option<usize>,
}

impl Default for KuramotoConfig {
    fn default() -> Self {
        Self {
            kernel_mode: MODE_ALL_TO_ALL_TICK.to_string(),
            seed: 20260621,
            gamma: 1.0,
            kc_expected: 2.0,
            n_values: vec![8, 16],
            k_values: vec![0.0, 2.0, 3.0],
            dt: 0.05,
            ticks: 40,
            plateau_window: 10,
            omega_clip: 10.0,
            series_sample_stride: 5,
            cli_sample_ticks: 3,
            topologies: default_topologies(),
            init_phase_mode: INIT_UNIFORM_SPREAD.to_string(),
            omega_assignment: OMEGA_LORENTZIAN_QUANTILE_GRID.to_string(),
            topology_relabel_seed: None,
            weight_policy: WEIGHT_POLICY_TOPOLOGY_DEFAULT.to_string(),
            phase_lag_alpha: None,
            coupling_radius: None,
            incoherent_fraction: None,
            emit_spatial_profiles: false,
            ablate_node: None,
        }
    }
}

fn default_kernel_mode() -> String {
    MODE_ALL_TO_ALL_TICK.to_string()
}

fn default_series_stride() -> usize {
    5
}

fn default_cli_sample_ticks() -> usize {
    3
}

fn default_topologies() -> Vec<String> {
    vec!["all_to_all".to_string()]
}

fn default_init_phase_mode() -> String {
    INIT_UNIFORM_SPREAD.to_string()
}

fn default_omega_assignment() -> String {
    OMEGA_LORENTZIAN_QUANTILE_GRID.to_string()
}

fn default_weight_policy() -> String {
    WEIGHT_POLICY_TOPOLOGY_DEFAULT.to_string()
}

#[derive(Debug)]
struct ExperimentArgs {
    kernel: PathBuf,
    compiler: PathBuf,
    out_dir: PathBuf,
    entry: String,
    config_path: Option<PathBuf>,
    cli_vm: PathBuf,
}

#[derive(Debug, Serialize)]
struct SummaryRow {
    topology: String,
    #[serde(rename = "N")]
    n: usize,
    #[serde(rename = "K")]
    k: f64,
    plateau_r: f64,
    #[serde(skip_serializing_if = "Option::is_none")]
    local_plateau_r: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    expected_r: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    residual_vs_mean_field: Option<f64>,
}

#[derive(Debug)]
struct SeriesRow {
    topology: String,
    n: usize,
    k: f64,
    tick: usize,
    global_r: f64,
    local_r_mean: Option<f64>,
}

#[derive(Debug)]
struct LocalOrderRow {
    topology: String,
    n: usize,
    k: f64,
    tick: usize,
    mean: f64,
    min: f64,
    max: f64,
}

#[derive(Clone, Debug, Serialize)]
struct NeighborEdge {
    target: usize,
    weight: f64,
}

#[derive(Clone, Debug, Serialize)]
struct Topology {
    name: String,
    n: usize,
    weight_policy: String,
    neighbors: Vec<Vec<NeighborEdge>>,
}

#[derive(Debug)]
struct ProfileRow {
    topology: String,
    n: usize,
    k: f64,
    node: usize,
    value: f64,
}

#[derive(Debug)]
struct SimulationResult {
    rows: Vec<SummaryRow>,
    series_rows: Vec<SeriesRow>,
    local_order_rows: Vec<LocalOrderRow>,
    topologies: Vec<Topology>,
    dispatch_us: Vec<u128>,
    tick_ms: Vec<f64>,
    // Per-node plateau-averaged spatial profiles (chimera measures): Z_i local order + Omega_i mean
    // phase velocity, plus the final per-node phase snapshot theta_i. Empty unless emit_spatial_profiles.
    spatial_profile_rows: Vec<ProfileRow>,
    omega_profile_rows: Vec<ProfileRow>,
    phase_snapshot_rows: Vec<ProfileRow>,
}

struct LoadedKernel {
    bytecode: Vec<crate::instructions::Instruction>,
    dispatch_table: HashMap<String, crate::vm::DispatchEntry>,
    functions: HashMap<String, FunctionEntry>,
    modifier: String,
    contract_name: String,
    compile_bytecode_ms: f64,
}

pub async fn handle_experiment(args: &[String]) -> Result<(), String> {
    if args.first().map(|s| s.as_str()) != Some("kuramoto") {
        return Err("usage: igniter-vm experiment kuramoto --kernel <path> --out <dir> [--compiler <path>] [--entry Tick] [--config <json>] [--cli-vm <path>]".to_string());
    }
    let parsed = parse_args(args)?;
    run_kuramoto(parsed).await
}

fn parse_args(args: &[String]) -> Result<ExperimentArgs, String> {
    let mut kernel = None;
    let mut compiler = None;
    let mut out_dir = None;
    let mut entry = "Tick".to_string();
    let mut config_path = None;
    let mut cli_vm = None;

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--kernel" => {
                kernel = Some(next_path(args, i, "--kernel")?);
                i += 2;
            }
            "--compiler" => {
                compiler = Some(next_path(args, i, "--compiler")?);
                i += 2;
            }
            "--out" => {
                out_dir = Some(next_path(args, i, "--out")?);
                i += 2;
            }
            "--entry" | "-e" => {
                entry = next_string(args, i, "--entry")?;
                i += 2;
            }
            "--config" => {
                config_path = Some(next_path(args, i, "--config")?);
                i += 2;
            }
            "--cli-vm" => {
                cli_vm = Some(next_path(args, i, "--cli-vm")?);
                i += 2;
            }
            "--help" | "-h" => {
                return Err("usage: igniter-vm experiment kuramoto --kernel <path> --out <dir> [--compiler <path>] [--entry Tick] [--config <json>] [--cli-vm <path>]".to_string());
            }
            other => return Err(format!("unknown experiment argument '{}'", other)),
        }
    }

    let kernel = kernel.ok_or("--kernel is required")?;
    let out_dir = out_dir.ok_or("--out is required")?;
    Ok(ExperimentArgs {
        kernel,
        compiler: compiler.unwrap_or_else(default_compiler_path),
        out_dir,
        entry,
        config_path,
        cli_vm: cli_vm.unwrap_or_else(default_vm_path),
    })
}

fn next_path(args: &[String], i: usize, name: &str) -> Result<PathBuf, String> {
    args.get(i + 1)
        .map(PathBuf::from)
        .ok_or_else(|| format!("{} requires a value", name))
}

fn next_string(args: &[String], i: usize, name: &str) -> Result<String, String> {
    args.get(i + 1)
        .cloned()
        .ok_or_else(|| format!("{} requires a value", name))
}

fn default_compiler_path() -> PathBuf {
    let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    let candidates = [
        cwd.join("../igniter-compiler/target/debug/igniter_compiler"),
        cwd.join("lang/igniter-compiler/target/debug/igniter_compiler"),
    ];
    candidates
        .iter()
        .find(|p| p.exists())
        .cloned()
        .unwrap_or_else(|| PathBuf::from("../igniter-compiler/target/debug/igniter_compiler"))
}

fn default_vm_path() -> PathBuf {
    std::env::current_exe().unwrap_or_else(|_| PathBuf::from("igniter-vm"))
}

async fn run_kuramoto(args: ExperimentArgs) -> Result<(), String> {
    if !args.kernel.exists() {
        return Err(format!("kernel not found: {}", args.kernel.display()));
    }
    if !args.compiler.exists() {
        return Err(format!("compiler not found: {}", args.compiler.display()));
    }

    fs::create_dir_all(&args.out_dir)
        .map_err(|e| format!("failed to create out dir {}: {}", args.out_dir.display(), e))?;
    let config = match load_config(args.config_path.as_deref()).and_then(|c| {
        validate_config(&c)?;
        Ok(c)
    }) {
        Ok(c) => c,
        Err(e) => return fail_stage(&args.out_dir, &args.entry, "config", e),
    };

    let run_started = chrono::Utc::now();
    let kernel_hash = match sha256_file(&args.kernel) {
        Ok(h) => h,
        Err(e) => return fail_stage(&args.out_dir, &args.entry, "kernel_hash", e),
    };
    let config_hash = sha256_text(&serde_json::to_string(&config).unwrap_or_default());
    let igapp_dir = args.out_dir.join("kernel.igapp");

    let compile_cli_start = Instant::now();
    if let Err(e) = compile_kernel(&args.compiler, &args.kernel, &igapp_dir) {
        return fail_stage(&args.out_dir, &args.entry, "compile_source_to_igapp", e);
    }
    let compile_cli_ms = compile_cli_start.elapsed().as_secs_f64() * 1000.0;

    let load_start = Instant::now();
    let sir_json = match load_sir(&igapp_dir) {
        Ok(v) => v,
        Err(e) => return fail_stage(&args.out_dir, &args.entry, "load_semantic_ir", e),
    };
    let sir_load_ms = load_start.elapsed().as_secs_f64() * 1000.0;
    let compiler_version = extract_compiler_version(&sir_json);
    let loaded = match load_kernel(sir_json, &args.entry) {
        Ok(k) => k,
        Err(e) => return fail_stage(&args.out_dir, &args.entry, "compile_bytecode_once", e),
    };

    let run_start = Instant::now();
    let simulation = match simulate(&config, &loaded).await {
        Ok(s) => s,
        Err(e) => return fail_stage(&args.out_dir, &args.entry, "run_ticks_inprocess", e),
    };
    let total_runtime_ms = run_start.elapsed().as_secs_f64() * 1000.0;

    let cli_compare = match run_cli_comparison(&args, &config, &igapp_dir).await {
        Ok(v) => v,
        Err(e) => json!({"status": "error", "error": e}),
    };

    write_bundle(
        &args,
        &config,
        &loaded,
        &simulation,
        BundleMeta {
            run_started,
            kernel_hash,
            config_hash,
            compile_cli_ms,
            sir_load_ms,
            total_runtime_ms,
            cli_compare,
            compiler_version,
            stdlib_version: igniter_stdlib::VERSION.to_string(),
            kernel_source: args.kernel.clone(),
        },
    )?;

    println!(
        "experiment_ok result_dir={} dispatches={} total_runtime_ms={:.3}",
        args.out_dir.display(),
        simulation.dispatch_us.len(),
        total_runtime_ms
    );
    Ok(())
}

fn load_config(path: Option<&Path>) -> Result<KuramotoConfig, String> {
    match path {
        Some(p) => {
            let text = fs::read_to_string(p)
                .map_err(|e| format!("failed to read config {}: {}", p.display(), e))?;
            serde_json::from_str(&text)
                .map_err(|e| format!("failed to parse config {}: {}", p.display(), e))
        }
        None => Ok(KuramotoConfig::default()),
    }
}

fn validate_config(config: &KuramotoConfig) -> Result<(), String> {
    if config.kernel_mode != MODE_ALL_TO_ALL_TICK && config.kernel_mode != MODE_NODE_TICK {
        return Err(format!(
            "config.kernel_mode must be '{}' or '{}'",
            MODE_ALL_TO_ALL_TICK, MODE_NODE_TICK
        ));
    }
    if config.n_values.is_empty() {
        return Err("config.n_values must not be empty".to_string());
    }
    if config.k_values.is_empty() {
        return Err("config.k_values must not be empty".to_string());
    }
    if config.ticks == 0 {
        return Err("config.ticks must be > 0".to_string());
    }
    if config.plateau_window == 0 || config.plateau_window > config.ticks {
        return Err("config.plateau_window must be in 1..=ticks".to_string());
    }
    if config.dt <= 0.0 {
        return Err("config.dt must be > 0".to_string());
    }
    match config.init_phase_mode.as_str() {
        INIT_UNIFORM_SPREAD | INIT_SHUFFLED_UNIFORM_SPREAD | INIT_LOCALIZED_CHIMERA_SEED => {}
        other => {
            return Err(format!(
                "config.init_phase_mode must be '{}', '{}', or '{}', got '{}'",
                INIT_UNIFORM_SPREAD,
                INIT_SHUFFLED_UNIFORM_SPREAD,
                INIT_LOCALIZED_CHIMERA_SEED,
                other
            ));
        }
    }
    if config.init_phase_mode == INIT_LOCALIZED_CHIMERA_SEED {
        let f = config.incoherent_fraction.unwrap_or(0.5);
        if !(f > 0.0 && f < 1.0) {
            return Err(
                "config.incoherent_fraction must be in (0,1) for localized_chimera_seed"
                    .to_string(),
            );
        }
    }
    match config.omega_assignment.as_str() {
        OMEGA_LORENTZIAN_QUANTILE_GRID | OMEGA_SHUFFLED_LORENTZIAN_QUANTILE_GRID => {}
        other => {
            return Err(format!(
                "config.omega_assignment must be '{}' or '{}', got '{}'",
                OMEGA_LORENTZIAN_QUANTILE_GRID, OMEGA_SHUFFLED_LORENTZIAN_QUANTILE_GRID, other
            ));
        }
    }
    if config.topology_relabel_seed.is_some() && config.kernel_mode != MODE_NODE_TICK {
        return Err(
            "config.topology_relabel_seed is only supported for node_tick mode".to_string(),
        );
    }
    match config.weight_policy.as_str() {
        WEIGHT_POLICY_TOPOLOGY_DEFAULT | WEIGHT_POLICY_DEGREE_NORMALIZED => {}
        other => {
            return Err(format!(
                "config.weight_policy must be '{}' or '{}', got '{}'",
                WEIGHT_POLICY_TOPOLOGY_DEFAULT, WEIGHT_POLICY_DEGREE_NORMALIZED, other
            ));
        }
    }
    if config.kernel_mode == MODE_NODE_TICK {
        if config.topologies.is_empty() {
            return Err("config.topologies must not be empty for node_tick mode".to_string());
        }
        for topology in &config.topologies {
            match topology.as_str() {
                "all_to_all" | "ring" | "grid" | "shuffled_ring" => {}
                TOPO_NONLOCAL_RING => {
                    let r = config.coupling_radius.unwrap_or(0);
                    for &n in &config.n_values {
                        if r < 1 || 2 * r >= n {
                            return Err(format!(
                                "nonlocal_ring requires config.coupling_radius in 1..N/2 (got R={}, N={})",
                                r, n
                            ));
                        }
                    }
                }
                other => {
                    return Err(format!(
                    "unsupported topology '{}'; expected all_to_all, ring, grid, shuffled_ring, or nonlocal_ring",
                    other
                ))
                }
            }
        }
        for &n in &config.n_values {
            if n < 2 {
                return Err("node_tick mode requires all N values to be >= 2".to_string());
            }
            if config.topologies.iter().any(|t| t == "grid") && !is_square(n) {
                return Err(format!("grid topology requires square N, got {}", n));
            }
        }
    }
    Ok(())
}

fn compile_kernel(compiler: &Path, kernel: &Path, igapp_dir: &Path) -> Result<(), String> {
    if igapp_dir.exists() {
        fs::remove_dir_all(igapp_dir)
            .map_err(|e| format!("failed to clear {}: {}", igapp_dir.display(), e))?;
    }
    let output = Command::new(compiler)
        .arg("compile")
        .arg(kernel)
        .arg("--out")
        .arg(igapp_dir)
        .output()
        .map_err(|e| format!("failed to run compiler {}: {}", compiler.display(), e))?;
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    let status_ok = serde_json::from_str::<JsonValue>(stdout.trim())
        .ok()
        .and_then(|v| v.get("status").and_then(|s| s.as_str()).map(|s| s == "ok"))
        .unwrap_or_else(|| {
            stdout.contains("\"status\": \"ok\"") || stdout.contains("\"status\":\"ok\"")
        });
    if !output.status.success() || !status_ok {
        return Err(format!(
            "kernel compile failed status={:?}\nstdout:\n{}\nstderr:\n{}",
            output.status.code(),
            stdout,
            stderr
        ));
    }
    Ok(())
}

fn load_sir(igapp_dir: &Path) -> Result<JsonValue, String> {
    let path = igapp_dir.join("semantic_ir_program.json");
    let text = fs::read_to_string(&path)
        .map_err(|e| format!("failed to read {}: {}", path.display(), e))?;
    serde_json::from_str(&text).map_err(|e| format!("failed to parse {}: {}", path.display(), e))
}

fn load_kernel(sir_json: JsonValue, entry: &str) -> Result<LoadedKernel, String> {
    let start = Instant::now();
    let mut compiler = Compiler::new();
    let bytecode = compiler.compile_entry(&sir_json, Some(entry))?;
    let mut dispatch_table = HashMap::new();
    let mut skipped = Vec::new();
    if let Some(contracts) = sir_json.get("contracts").and_then(|c| c.as_array()) {
        for contract in contracts {
            let name = contract_display_name(contract);
            if name.is_empty() {
                continue;
            }
            match compiler.build_dispatch_entry(contract, &name) {
                Ok(entry) => {
                    dispatch_table.insert(name, entry);
                }
                Err(e) => skipped.push((name, e)),
            }
        }
    }
    if !skipped.is_empty() {
        return Err(format!("dispatch table construction failed: {:?}", skipped));
    }
    let contract = select_contract(&sir_json, entry)?;
    let modifier = contract
        .get("modifier")
        .and_then(|m| m.as_str())
        .unwrap_or("pure")
        .to_string();
    let contract_name = contract_display_name(contract);
    let functions = build_function_registry(&sir_json);
    Ok(LoadedKernel {
        bytecode,
        dispatch_table,
        functions,
        modifier,
        contract_name,
        compile_bytecode_ms: start.elapsed().as_secs_f64() * 1000.0,
    })
}

fn select_contract<'a>(sir_json: &'a JsonValue, entry: &str) -> Result<&'a JsonValue, String> {
    sir_json
        .get("contracts")
        .and_then(|c| c.as_array())
        .and_then(|contracts| {
            contracts.iter().find(|c| {
                c.get("contract_name").and_then(|n| n.as_str()) == Some(entry)
                    || c.get("name").and_then(|n| n.as_str()) == Some(entry)
            })
        })
        .ok_or_else(|| format!("entry contract '{}' not found", entry))
}

fn contract_display_name(contract: &JsonValue) -> String {
    contract
        .get("contract_name")
        .or_else(|| contract.get("name"))
        .or_else(|| contract.get("contract_id"))
        .and_then(|n| n.as_str())
        .unwrap_or("")
        .to_string()
}

fn build_function_registry(sir_json: &JsonValue) -> HashMap<String, FunctionEntry> {
    let mut registry = HashMap::new();
    if let Some(funcs) = sir_json.get("functions").and_then(|f| f.as_array()) {
        for f in funcs {
            let name = f
                .get("name")
                .and_then(|n| n.as_str())
                .unwrap_or("")
                .to_string();
            if name.is_empty() {
                continue;
            }
            let params = f
                .get("params")
                .and_then(|p| p.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter_map(|p| {
                            p.get("name")
                                .and_then(|n| n.as_str())
                                .map(String::from)
                                .or_else(|| p.as_str().map(String::from))
                        })
                        .collect()
                })
                .unwrap_or_default();
            let body = f.get("body").cloned().unwrap_or(JsonValue::Null);
            registry.insert(name, FunctionEntry { params, body });
        }
    }
    registry
}

async fn simulate(
    config: &KuramotoConfig,
    loaded: &LoadedKernel,
) -> Result<SimulationResult, String> {
    if config.kernel_mode == MODE_NODE_TICK {
        simulate_node_tick(config, loaded).await
    } else {
        simulate_all_to_all_tick(config, loaded).await
    }
}

async fn simulate_all_to_all_tick(
    config: &KuramotoConfig,
    loaded: &LoadedKernel,
) -> Result<SimulationResult, String> {
    let mut rows = Vec::new();
    let mut series_rows = Vec::new();
    let local_order_rows = Vec::new();
    let mut topologies = Vec::new();
    let mut dispatch_us = Vec::new();
    let mut tick_ms = Vec::new();

    for &n in &config.n_values {
        topologies.push(build_topology("all_to_all", n, config.seed, None)?);
        let omegas = omega_vector_for_config(n, config);
        for &k in &config.k_values {
            let mut thetas = init_phases_for_config(n, config);
            let mut r_series = Vec::new();
            for tick in 0..config.ticks {
                let tick_start = Instant::now();
                let (next, elapsed_us) =
                    execute_tick(loaded, &thetas, &omegas, k / n as f64, config.dt).await?;
                thetas = next.into_iter().map(wrap_phase).collect();
                let tick_elapsed = tick_start.elapsed().as_secs_f64() * 1000.0;
                dispatch_us.push(elapsed_us);
                tick_ms.push(tick_elapsed);
                let r = order_parameter(&thetas);
                r_series.push(r);
                if config.series_sample_stride == 0 || tick % config.series_sample_stride == 0 {
                    series_rows.push(SeriesRow {
                        topology: "all_to_all".to_string(),
                        n,
                        k,
                        tick,
                        global_r: r,
                        local_r_mean: None,
                    });
                }
            }
            let plateau = mean(&r_series[r_series.len() - config.plateau_window..]);
            let expected = expected_r(k, config.kc_expected);
            rows.push(SummaryRow {
                topology: "all_to_all".to_string(),
                n,
                k,
                plateau_r: plateau,
                local_plateau_r: None,
                expected_r: Some(expected),
                residual_vs_mean_field: Some(plateau - expected),
            });
        }
    }

    Ok(SimulationResult {
        rows,
        series_rows,
        local_order_rows,
        topologies,
        dispatch_us,
        tick_ms,
        spatial_profile_rows: Vec::new(),
        omega_profile_rows: Vec::new(),
        phase_snapshot_rows: Vec::new(),
    })
}

async fn simulate_node_tick(
    config: &KuramotoConfig,
    loaded: &LoadedKernel,
) -> Result<SimulationResult, String> {
    let mut rows = Vec::new();
    let mut series_rows = Vec::new();
    let mut local_order_rows = Vec::new();
    let mut topologies_out = Vec::new();
    let mut dispatch_us = Vec::new();
    let mut tick_ms = Vec::new();
    let mut spatial_profile_rows = Vec::new();
    let mut omega_profile_rows = Vec::new();
    let mut phase_snapshot_rows = Vec::new();
    let plateau_start = config.ticks - config.plateau_window;

    for &n in &config.n_values {
        let omegas = omega_vector_for_config(n, config);
        let mut topologies = build_topologies_for_config(n, config)?;
        // EMERGENCE-STAGE2-ABLATION-MAP-P16: knockout — drop every edge that targets the ablated node, so it
        // exerts no coupling on the surviving dynamics (it is also excluded from the order parameter below).
        if let Some(ablate) = config.ablate_node {
            if ablate < n {
                for topology in &mut topologies {
                    for nbrs in &mut topology.neighbors {
                        nbrs.retain(|edge| edge.target != ablate);
                    }
                }
            }
        }
        topologies_out.extend(topologies.iter().cloned());

        for topology in &topologies {
            for &k in &config.k_values {
                let mut thetas = init_phases_for_config(n, config);
                let mut global_r_series = Vec::new();
                let mut local_r_series = Vec::new();
                // Per-node plateau accumulators for the chimera spatial measures.
                let mut z_accum = vec![0.0_f64; n];
                let mut omega_accum = vec![0.0_f64; n];

                for tick in 0..config.ticks {
                    let tick_start = Instant::now();
                    let snapshot = thetas.clone();
                    let mut next_thetas = Vec::with_capacity(n);

                    for node_idx in 0..n {
                        let (next_theta, elapsed_us) = execute_node_tick(
                            loaded,
                            &snapshot,
                            &omegas,
                            topology,
                            node_idx,
                            k,
                            config.dt,
                            config.phase_lag_alpha,
                        )
                        .await?;
                        next_thetas.push(next_theta);
                        dispatch_us.push(elapsed_us);
                    }

                    // Mean phase velocity Omega_i: accumulate the RAW per-tick increment (pre-wrap,
                    // a single small Euler step so no 2pi ambiguity) over the plateau window.
                    if config.emit_spatial_profiles && tick >= plateau_start {
                        for i in 0..n {
                            omega_accum[i] += next_thetas[i] - snapshot[i];
                        }
                    }

                    thetas = next_thetas.iter().map(|&t| wrap_phase(t)).collect();
                    tick_ms.push(tick_start.elapsed().as_secs_f64() * 1000.0);

                    let local_profile = local_order_profile(&thetas, topology);
                    // P16: the ablated node is excluded from the macro order parameter (it has been removed
                    // from the system), so the global r is measured over the surviving oscillators only.
                    let global_r = match config.ablate_node {
                        Some(a) if a < n => {
                            let survivors: Vec<f64> = thetas
                                .iter()
                                .enumerate()
                                .filter(|(i, _)| *i != a)
                                .map(|(_, &t)| t)
                                .collect();
                            order_parameter(&survivors)
                        }
                        _ => order_parameter(&thetas),
                    };
                    let local_stats = stats_from_profile(&local_profile);
                    global_r_series.push(global_r);
                    local_r_series.push(local_stats.mean);
                    // Local order profile Z_i: accumulate over the plateau window.
                    if config.emit_spatial_profiles && tick >= plateau_start {
                        for i in 0..n {
                            z_accum[i] += local_profile[i];
                        }
                    }

                    if config.series_sample_stride == 0 || tick % config.series_sample_stride == 0 {
                        series_rows.push(SeriesRow {
                            topology: topology.name.clone(),
                            n,
                            k,
                            tick,
                            global_r,
                            local_r_mean: Some(local_stats.mean),
                        });
                        local_order_rows.push(LocalOrderRow {
                            topology: topology.name.clone(),
                            n,
                            k,
                            tick,
                            mean: local_stats.mean,
                            min: local_stats.min,
                            max: local_stats.max,
                        });
                    }
                }

                let plateau =
                    mean(&global_r_series[global_r_series.len() - config.plateau_window..]);
                let local_plateau =
                    mean(&local_r_series[local_r_series.len() - config.plateau_window..]);
                let expected = if topology.name == "all_to_all" {
                    Some(expected_r(k, config.kc_expected))
                } else {
                    None
                };
                rows.push(SummaryRow {
                    topology: topology.name.clone(),
                    n,
                    k,
                    plateau_r: plateau,
                    local_plateau_r: Some(local_plateau),
                    expected_r: expected,
                    residual_vs_mean_field: expected.map(|target| plateau - target),
                });

                if config.emit_spatial_profiles {
                    let w = config.plateau_window as f64;
                    for i in 0..n {
                        spatial_profile_rows.push(ProfileRow {
                            topology: topology.name.clone(),
                            n,
                            k,
                            node: i,
                            value: z_accum[i] / w,
                        });
                        omega_profile_rows.push(ProfileRow {
                            topology: topology.name.clone(),
                            n,
                            k,
                            node: i,
                            value: omega_accum[i] / (w * config.dt),
                        });
                        phase_snapshot_rows.push(ProfileRow {
                            topology: topology.name.clone(),
                            n,
                            k,
                            node: i,
                            value: thetas[i],
                        });
                    }
                }
            }
        }
    }

    Ok(SimulationResult {
        rows,
        series_rows,
        local_order_rows,
        topologies: topologies_out,
        dispatch_us,
        tick_ms,
        spatial_profile_rows,
        omega_profile_rows,
        phase_snapshot_rows,
    })
}

async fn execute_tick(
    loaded: &LoadedKernel,
    thetas: &[f64],
    omegas: &[f64],
    k_over_n: f64,
    dt: f64,
) -> Result<(Vec<f64>, u128), String> {
    let nodes: Vec<JsonValue> = thetas
        .iter()
        .zip(omegas.iter())
        .map(|(theta, omega)| json!({"theta": theta, "omega": omega}))
        .collect();
    let inputs_json = json!({"nodes": nodes, "k_over_n": k_over_n, "dt": dt});
    let mut inputs = HashMap::new();
    if let Some(obj) = inputs_json.as_object() {
        for (k, v) in obj {
            inputs.insert(k.clone(), Value::from_json(v));
        }
    }
    let (out, elapsed) = execute_loaded(loaded, &inputs).await?;
    let values = floats_from_value(&out)?;
    if values.len() != thetas.len() {
        return Err(format!(
            "contract={} output length {} != input length {}",
            loaded.contract_name,
            values.len(),
            thetas.len()
        ));
    }
    Ok((values, elapsed))
}

async fn execute_node_tick(
    loaded: &LoadedKernel,
    snapshot_thetas: &[f64],
    omegas: &[f64],
    topology: &Topology,
    node_idx: usize,
    k_value: f64,
    dt: f64,
    alpha: Option<f64>,
) -> Result<(f64, u128), String> {
    let neighbors: Vec<JsonValue> = topology.neighbors[node_idx]
        .iter()
        .map(|edge| json!({"theta": snapshot_thetas[edge.target], "weight": edge.weight}))
        .collect();
    // `alpha` is added only for the Kuramoto-Sakaguchi kernel; legacy node_tick kernels (no alpha
    // input) are driven with the original input set so their bundles stay byte-identical.
    let inputs_json = match alpha {
        Some(a) => json!({
            "self": {"theta": snapshot_thetas[node_idx], "omega": omegas[node_idx]},
            "neighbors": neighbors,
            "k": k_value,
            "alpha": a,
            "dt": dt
        }),
        None => json!({
            "self": {"theta": snapshot_thetas[node_idx], "omega": omegas[node_idx]},
            "neighbors": neighbors,
            "k": k_value,
            "dt": dt
        }),
    };
    let mut inputs = HashMap::new();
    if let Some(obj) = inputs_json.as_object() {
        for (k, v) in obj {
            inputs.insert(k.clone(), Value::from_json(v));
        }
    }
    let (out, elapsed) = execute_loaded(loaded, &inputs).await?;
    let theta = float_from_value(&out)?;
    Ok((theta, elapsed))
}

async fn execute_loaded(
    loaded: &LoadedKernel,
    inputs: &HashMap<String, Value>,
) -> Result<(Value, u128), String> {
    let mut temporal = HashMap::new();
    temporal.insert(
        "contract_modifier".to_string(),
        Value::String(Arc::from(loaded.modifier.as_str())),
    );
    temporal.insert(
        "__call_chain__".to_string(),
        Value::String(Arc::from(loaded.contract_name.as_str())),
    );
    let backend: Option<Arc<dyn TBackend>> = Some(Arc::new(MemoryHistoryBackend::new()));
    let mut vm = VM::new(backend);
    vm.dispatch_table = loaded.dispatch_table.clone();
    vm.functions = loaded.functions.clone();

    let start = Instant::now();
    let out = vm
        .execute(&loaded.bytecode, inputs, &temporal)
        .await
        .map_err(|e| format!("contract={} error={}", loaded.contract_name, e))?;
    Ok((out, start.elapsed().as_micros()))
}

fn floats_from_value(value: &Value) -> Result<Vec<f64>, String> {
    match value {
        Value::Array(arr) => arr.iter().map(float_from_value).collect(),
        other => Err(format!("expected Array output, got {:?}", other)),
    }
}

fn float_from_value(value: &Value) -> Result<f64, String> {
    match value {
        Value::Float(f) if f.is_finite() => Ok(*f),
        Value::Integer(i) => Ok(*i as f64),
        other => Err(format!("expected finite Float output, got {:?}", other)),
    }
}

async fn run_cli_comparison(
    args: &ExperimentArgs,
    config: &KuramotoConfig,
    igapp_dir: &Path,
) -> Result<JsonValue, String> {
    if config.kernel_mode == MODE_NODE_TICK {
        return Ok(json!({
            "status": "skipped",
            "reason": "node_tick mode performs N in-process dispatches per tick; CLI comparison belongs to P5 all_to_all_tick mode"
        }));
    }
    if config.cli_sample_ticks == 0 {
        return Ok(json!({
            "status": "skipped",
            "reason": "config.cli_sample_ticks=0"
        }));
    }
    let n = *config.n_values.first().ok_or("empty n_values")?;
    let k = *config.k_values.last().ok_or("empty k_values")?;
    let sample_ticks = config.cli_sample_ticks.min(config.ticks).max(1);
    let omegas = omega_vector_for_config(n, config);
    let mut thetas = init_phases_for_config(n, config);
    let mut dispatch_us = Vec::new();
    let tmp = args.out_dir.join("_cli_compare_inputs.json");
    for tick in 0..sample_ticks {
        let nodes: Vec<JsonValue> = thetas
            .iter()
            .zip(omegas.iter())
            .map(|(theta, omega)| json!({"theta": theta, "omega": omega}))
            .collect();
        let inputs_json = json!({"nodes": nodes, "k_over_n": k / n as f64, "dt": config.dt});
        fs::write(&tmp, serde_json::to_vec(&inputs_json).unwrap_or_default())
            .map_err(|e| format!("failed to write CLI comparison inputs: {}", e))?;
        let start = Instant::now();
        let output = Command::new(&args.cli_vm)
            .arg("run")
            .arg("--json")
            .arg("--contract")
            .arg(igapp_dir)
            .arg("--entry")
            .arg(&args.entry)
            .arg("--inputs")
            .arg(&tmp)
            .output()
            .map_err(|e| format!("failed to run CLI VM {}: {}", args.cli_vm.display(), e))?;
        let elapsed = start.elapsed().as_micros();
        if !output.status.success() {
            return Err(format!(
                "CLI comparison failed at tick {} status={:?} stderr={}",
                tick,
                output.status.code(),
                String::from_utf8_lossy(&output.stderr)
            ));
        }
        let stdout = String::from_utf8_lossy(&output.stdout);
        let response: JsonValue = serde_json::from_str(stdout.trim()).map_err(|e| {
            format!(
                "failed to parse CLI JSON at tick {}: {} stdout={}",
                tick, e, stdout
            )
        })?;
        if response.get("status").and_then(|v| v.as_str()) != Some("success") {
            return Err(format!(
                "CLI comparison returned non-success at tick {}: {}",
                tick, response
            ));
        }
        let result = response
            .get("result")
            .ok_or_else(|| format!("CLI comparison missing result at tick {}", tick))?;
        let values: Vec<f64> = result
            .as_array()
            .ok_or_else(|| format!("CLI comparison result is not array at tick {}", tick))?
            .iter()
            .map(|v| {
                v.as_f64()
                    .ok_or_else(|| format!("non-float CLI result at tick {}", tick))
            })
            .collect::<Result<Vec<_>, _>>()?;
        thetas = values.into_iter().map(wrap_phase).collect();
        dispatch_us.push(elapsed);
    }
    let _ = fs::remove_file(tmp);
    Ok(json!({
        "status": "ok",
        "sample_ticks": sample_ticks,
        "N": n,
        "K": k,
        "total_us": dispatch_us.iter().sum::<u128>(),
        "mean_us": mean_u128(&dispatch_us),
        "min_us": dispatch_us.iter().min().cloned().unwrap_or(0),
        "max_us": dispatch_us.iter().max().cloned().unwrap_or(0)
    }))
}

struct BundleMeta {
    run_started: chrono::DateTime<chrono::Utc>,
    kernel_hash: String,
    config_hash: String,
    compile_cli_ms: f64,
    sir_load_ms: f64,
    total_runtime_ms: f64,
    cli_compare: JsonValue,
    compiler_version: String,
    stdlib_version: String,
    kernel_source: PathBuf,
}

fn write_bundle(
    args: &ExperimentArgs,
    config: &KuramotoConfig,
    loaded: &LoadedKernel,
    simulation: &SimulationResult,
    meta: BundleMeta,
) -> Result<(), String> {
    let inprocess_mean = mean_u128(&simulation.dispatch_us);
    let cli_mean = meta
        .cli_compare
        .get("mean_us")
        .and_then(|v| v.as_f64())
        .unwrap_or(0.0);
    let speedup = if cli_mean > 0.0 && inprocess_mean > 0.0 {
        Some(cli_mean / inprocess_mean)
    } else {
        None
    };

    let topology_out = json!({
        "kernel_mode": config.kernel_mode,
        "sync_barrier": "strict_jacobi: read all node states at tick t, compute all next states from snapshot t, commit together to t+1",
        "topologies": simulation.topologies,
    });
    let topology_hash = sha256_text(&serde_json::to_string(&topology_out).unwrap_or_default());

    let config_out = json!({
        "runner": "igniter-vm experiment kuramoto",
        "kernel_mode": config.kernel_mode,
        "kernel": args.kernel,
        "entry": args.entry,
        "seed": config.seed,
        "gamma": config.gamma,
        "kc_expected": config.kc_expected,
        "n_values": config.n_values,
        "k_values": config.k_values,
        "topologies": config.topologies,
        "dt": config.dt,
        "ticks": config.ticks,
        "plateau_window": config.plateau_window,
        "omega_clip": config.omega_clip,
        "omega_method": "lorentzian_quantile_grid: omega_i = gamma*tan(pi*((i+0.5)/N - 0.5)), clipped",
        "omega_assignment": &config.omega_assignment,
        "init_phase_mode": &config.init_phase_mode,
        "init_phases": match config.init_phase_mode.as_str() {
            INIT_SHUFFLED_UNIFORM_SPREAD => {
                "shuffled_uniform_spread: deterministic seed shuffle of theta_i = 2*pi*i/N".to_string()
            }
            INIT_LOCALIZED_CHIMERA_SEED => format!(
                "localized_chimera_seed: central band |i/N-0.5|<{}/2 gets theta_i=2*pi*frac((i+1)*{:.16}); rest theta_i=0",
                config.incoherent_fraction.unwrap_or(0.5),
                GOLDEN_RATIO_FRAC
            ),
            _ => "uniform_spread: theta_i = 2*pi*i/N".to_string(),
        },
        "phase_lag_alpha": config.phase_lag_alpha,
        "coupling_radius": config.coupling_radius,
        "incoherent_fraction": config.incoherent_fraction,
        "ablate_node": config.ablate_node,
        "coupling_form": if config.phase_lag_alpha.is_some() {
            "sakaguchi: sin(theta_j - theta_i - alpha)"
        } else {
            "plain: sin(theta_j - theta_i)"
        },
        "topology_relabel_seed": config.topology_relabel_seed,
        "weight_policy": &config.weight_policy,
        "integrator": "explicit_euler",
        "kernel_sha256": meta.kernel_hash,
        "config_sha256": meta.config_hash,
        "topology_sha256": topology_hash,
        "contract_name": loaded.contract_name,
    });
    write_json(args.out_dir.join("config.json"), &config_out)?;
    write_json(args.out_dir.join("topology.json"), &topology_out)?;

    let provenance = build_provenance_json(
        &config.kernel_mode,
        &args.entry,
        &meta.kernel_source,
        &meta.kernel_hash,
        &meta.config_hash,
        &meta.compiler_version,
        &meta.stdlib_version,
        None,
    );
    write_json(args.out_dir.join("provenance.json"), &provenance)?;

    let mut series = String::from("topology,N,K,tick,global_r,local_r_mean\n");
    for row in &simulation.series_rows {
        series.push_str(&format!(
            "{},{},{},{},{},{}\n",
            row.topology,
            row.n,
            row.k,
            row.tick,
            row.global_r,
            row.local_r_mean.map(|v| v.to_string()).unwrap_or_default()
        ));
    }
    fs::write(args.out_dir.join("series.csv"), series)
        .map_err(|e| format!("failed to write series.csv: {}", e))?;

    let mut local_order = String::from("topology,N,K,tick,mean_local_r,min_local_r,max_local_r\n");
    for row in &simulation.local_order_rows {
        local_order.push_str(&format!(
            "{},{},{},{},{},{},{}\n",
            row.topology, row.n, row.k, row.tick, row.mean, row.min, row.max
        ));
    }
    fs::write(args.out_dir.join("local_order.csv"), local_order)
        .map_err(|e| format!("failed to write local_order.csv: {}", e))?;

    if config.emit_spatial_profiles {
        let mut spatial = String::from("topology,N,K,node,plateau_local_r\n");
        for row in &simulation.spatial_profile_rows {
            spatial.push_str(&format!(
                "{},{},{},{},{}\n",
                row.topology, row.n, row.k, row.node, row.value
            ));
        }
        fs::write(args.out_dir.join("spatial_profile.csv"), spatial)
            .map_err(|e| format!("failed to write spatial_profile.csv: {}", e))?;

        let mut omega = String::from("topology,N,K,node,mean_phase_velocity\n");
        for row in &simulation.omega_profile_rows {
            omega.push_str(&format!(
                "{},{},{},{},{}\n",
                row.topology, row.n, row.k, row.node, row.value
            ));
        }
        fs::write(args.out_dir.join("omega_profile.csv"), omega)
            .map_err(|e| format!("failed to write omega_profile.csv: {}", e))?;

        let mut snap = String::from("topology,N,K,node,theta\n");
        for row in &simulation.phase_snapshot_rows {
            snap.push_str(&format!(
                "{},{},{},{},{}\n",
                row.topology, row.n, row.k, row.node, row.value
            ));
        }
        fs::write(args.out_dir.join("phase_snapshot.csv"), snap)
            .map_err(|e| format!("failed to write phase_snapshot.csv: {}", e))?;
    }

    let transition_observed = simulation.rows.iter().any(|r| {
        r.topology == "all_to_all" && r.k >= config.kc_expected * 1.5 && r.plateau_r > 0.4
    });
    let summary = json!({
        "status": "ok",
        "run_started_utc": meta.run_started.to_rfc3339(),
        "kernel_mode": config.kernel_mode,
        "measurement_math": "deterministic_libm",
        "rows": simulation.rows,
        "transition_observed": transition_observed,
        "inprocess_dispatches": simulation.dispatch_us.len(),
        "timing_headline": {
            "cli_mean_us": cli_mean,
            "inprocess_mean_us": inprocess_mean,
            "speedup_cli_mean_over_inprocess_mean": speedup
        }
    });
    write_json(args.out_dir.join("summary.json"), &summary)?;

    let timings = json!({
        "compile_source_to_igapp_ms": meta.compile_cli_ms,
        "sir_load_ms": meta.sir_load_ms,
        "bytecode_compile_once_ms": loaded.compile_bytecode_ms,
        "total_runtime_ms": meta.total_runtime_ms,
        "dispatch_us": summarize_u128(&simulation.dispatch_us),
        "tick_ms": summarize_f64(&simulation.tick_ms),
        "cli_per_tick_comparison": meta.cli_compare,
    });
    write_json(args.out_dir.join("timings.json"), &timings)?;
    write_report(args, config, &summary, &timings, speedup, &provenance)?;
    Ok(())
}

fn write_report(
    args: &ExperimentArgs,
    config: &KuramotoConfig,
    summary: &JsonValue,
    timings: &JsonValue,
    speedup: Option<f64>,
    provenance: &JsonValue,
) -> Result<(), String> {
    let mut text = String::new();
    text.push_str("# In-process Kuramoto runner proof\n\n");
    if config.kernel_mode == MODE_NODE_TICK {
        text.push_str("LAB-IGNITER-EMERGENCE-LOCAL-MULTINODE-SIM-P6. Deterministic local multi-node reference, not a distributed system and not a new scientific claim.\n\n");
        text.push_str("Strict barrier semantics: read every node state at tick t, compute every next state from that snapshot, then commit all states together to t+1.\n\n");
    } else {
        text.push_str("LAB-IGNITER-EXPERIMENT-INPROCESS-RUNNER-P5. Apparatus infrastructure, not a new scientific claim.\n\n");
    }
    text.push_str("## Command\n\n```text\n");
    text.push_str("igniter-vm experiment kuramoto --kernel ");
    text.push_str(&args.kernel.display().to_string());
    text.push_str(" --entry ");
    text.push_str(&args.entry);
    text.push_str(" --out ");
    text.push_str(&args.out_dir.display().to_string());
    text.push_str("\n```\n\n");
    text.push_str("## Config\n\n```json\n");
    text.push_str(&serde_json::to_string_pretty(config).unwrap_or_default());
    text.push_str("\n```\n\n");
    text.push_str("## Timing headline\n\n");
    let cli_mean = timings
        .get("cli_per_tick_comparison")
        .and_then(|v| v.get("mean_us"))
        .and_then(|v| v.as_f64())
        .unwrap_or(0.0);
    let inprocess_mean = timings
        .get("dispatch_us")
        .and_then(|v| v.get("mean"))
        .and_then(|v| v.as_f64())
        .unwrap_or(0.0);
    text.push_str(&format!(
        "- CLI per-tick mean: {:.1} us\n- In-process dispatch mean: {:.1} us\n",
        cli_mean, inprocess_mean
    ));
    if config.kernel_mode == MODE_NODE_TICK && cli_mean == 0.0 {
        text.push_str("- CLI comparison: skipped for node_tick mode\n");
    }
    if let Some(s) = speedup {
        text.push_str(&format!("- CLI/in-process mean ratio: {:.1}x\n", s));
    }
    text.push_str("\n## Summary\n\n```json\n");
    text.push_str(&serde_json::to_string_pretty(summary).unwrap_or_default());
    text.push_str("\n```\n\n");
    text.push_str("## Provenance\n\nSee `provenance.json` (schema: `");
    text.push_str(
        provenance
            .get("schema")
            .and_then(|v| v.as_str())
            .unwrap_or("igniter.experiment.provenance.v1"),
    );
    text.push_str("`).\n\n");
    text.push_str("| Field | Value |\n|---|---|\n");
    for key in &[
        "runner",
        "runner_mode",
        "entry",
        "kernel_source",
        "kernel_digest",
        "config_digest",
        "compiler_version",
        "stdlib_version",
    ] {
        let val = provenance.get(*key).and_then(|v| v.as_str()).unwrap_or("-");
        text.push_str(&format!("| {} | `{}` |\n", key, val));
    }
    text.push('\n');
    text.push_str("## Failure policy\n\nKernel compile/load errors and VM tick errors exit non-zero. Runtime tick failures write `failure.json` with contract/tick/error context before returning failure.\n");
    fs::write(args.out_dir.join("REPORT.md"), text)
        .map_err(|e| format!("failed to write REPORT.md: {}", e))
}

fn extract_compiler_version(sir_json: &JsonValue) -> String {
    let fmt = sir_json
        .get("format_version")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown");
    let grammar = sir_json
        .get("grammar_version")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown");
    format!("{}/{}", fmt, grammar)
}

fn build_provenance_json(
    runner_mode: &str,
    entry: &str,
    kernel_source: &Path,
    kernel_digest: &str,
    config_digest: &str,
    compiler_version: &str,
    stdlib_version: &str,
    artifact_digest: Option<&str>,
) -> JsonValue {
    json!({
        "schema": "igniter.experiment.provenance.v1",
        "runner": "igniter-vm experiment kuramoto",
        "runner_mode": runner_mode,
        "entry": entry,
        "kernel_source": kernel_source.display().to_string(),
        "kernel_digest": kernel_digest,
        "config_digest": config_digest,
        "compiler_version": compiler_version,
        "stdlib_version": stdlib_version,
        "artifact_digest": artifact_digest
    })
}

fn write_failure(out_dir: &Path, contract: &str, stage: &str, error: &str) -> Result<(), String> {
    let failure = json!({
        "status": "error",
        "stage": stage,
        "contract": contract,
        "error": error,
        "recorded_at_utc": chrono::Utc::now().to_rfc3339()
    });
    write_json(out_dir.join("failure.json"), &failure)?;
    let mut report = fs::File::create(out_dir.join("REPORT.md"))
        .map_err(|e| format!("failed to write failure REPORT.md: {}", e))?;
    writeln!(report, "# In-process Kuramoto runner failure").ok();
    writeln!(
        report,
        "\n```json\n{}\n```",
        serde_json::to_string_pretty(&failure).unwrap_or_default()
    )
    .ok();
    Ok(())
}

fn write_json(path: PathBuf, value: &JsonValue) -> Result<(), String> {
    let mut text = serde_json::to_string_pretty(value).unwrap_or_default();
    text.push('\n');
    fs::write(&path, text).map_err(|e| format!("failed to write {}: {}", path.display(), e))
}

fn omega_vector(n: usize, gamma: f64, clip: f64) -> Vec<f64> {
    (0..n)
        .map(|i| {
            let u = (i as f64 + 0.5) / n as f64;
            let w = gamma * (std::f64::consts::PI * (u - 0.5)).tan();
            w.max(-clip * gamma).min(clip * gamma)
        })
        .collect()
}

fn omega_vector_for_config(n: usize, config: &KuramotoConfig) -> Vec<f64> {
    let values = omega_vector(n, config.gamma, config.omega_clip);
    if config.omega_assignment == OMEGA_SHUFFLED_LORENTZIAN_QUANTILE_GRID {
        permute_values(&values, config.seed ^ 0x51f1_5eED_0bA5_E0A1)
    } else {
        values
    }
}

fn init_phases(n: usize) -> Vec<f64> {
    (0..n).map(|i| TWO_PI * i as f64 / n as f64).collect()
}

fn init_phases_for_config(n: usize, config: &KuramotoConfig) -> Vec<f64> {
    match config.init_phase_mode.as_str() {
        INIT_SHUFFLED_UNIFORM_SPREAD => {
            permute_values(&init_phases(n), config.seed ^ 0xA11c_Ec0d_E001_D15c)
        }
        INIT_LOCALIZED_CHIMERA_SEED => {
            localized_chimera_phases(n, config.incoherent_fraction.unwrap_or(0.5))
        }
        _ => init_phases(n),
    }
}

// Deterministic localized chimera seed: a contiguous incoherent band of width `fraction`, centred on
// the ring, gets a golden-ratio low-discrepancy phase scramble in [0,2pi); the rest is a coherent
// sea at phase 0. Pure function of (i, n, fraction) — no PRNG state — so replay is exact. This breaks
// the ring symmetry locally, the standard basin for a coexisting coherent/incoherent (chimera) state.
fn localized_chimera_phases(n: usize, fraction: f64) -> Vec<f64> {
    let half = fraction / 2.0;
    (0..n)
        .map(|i| {
            let x = i as f64 / n as f64;
            if (x - 0.5).abs() < half {
                TWO_PI * ((i as f64 + 1.0) * GOLDEN_RATIO_FRAC).fract()
            } else {
                0.0
            }
        })
        .collect()
}

fn order_parameter(thetas: &[f64]) -> f64 {
    // EMERGENCE-DETERMINISTIC-MEASUREMENT-P13: deterministic-by-construction readout. Use the same vendored
    // `libm` the det_* surface uses (NOT platform std cos/sin), so global/local r (and the chimera Z_i that
    // routes through here) are bit-identical across architectures by construction, not merely by observation.
    // `sqrt` is IEEE-754 correctly-rounded → already portable, left as-is.
    let n = thetas.len() as f64;
    let c = thetas.iter().map(|t| libm::cos(*t)).sum::<f64>() / n;
    let s = thetas.iter().map(|t| libm::sin(*t)).sum::<f64>() / n;
    (c * c + s * s).sqrt()
}

fn expected_r(k: f64, kc: f64) -> f64 {
    if k > kc {
        (1.0 - kc / k).sqrt()
    } else {
        0.0
    }
}

#[derive(Clone, Copy, Debug)]
struct LocalOrderStats {
    mean: f64,
    min: f64,
    max: f64,
}

// Per-node local order Z_i = |mean e^{i theta}| over node i and its coupling neighbourhood. The full
// vector IS the chimera spatial signature (a contiguous high-Z arc + a low-Z arc); reducers below.
fn local_order_profile(thetas: &[f64], topology: &Topology) -> Vec<f64> {
    let mut local = Vec::with_capacity(thetas.len());
    for (idx, theta) in thetas.iter().enumerate() {
        let mut phases = Vec::with_capacity(topology.neighbors[idx].len() + 1);
        phases.push(*theta);
        for edge in &topology.neighbors[idx] {
            phases.push(thetas[edge.target]);
        }
        local.push(order_parameter(&phases));
    }
    local
}

fn stats_from_profile(local: &[f64]) -> LocalOrderStats {
    LocalOrderStats {
        mean: mean(local),
        min: local.iter().cloned().reduce(f64::min).unwrap_or(0.0),
        max: local.iter().cloned().reduce(f64::max).unwrap_or(0.0),
    }
}

fn build_topologies(
    n: usize,
    names: &[String],
    seed: u64,
    radius: Option<usize>,
) -> Result<Vec<Topology>, String> {
    names
        .iter()
        .map(|name| build_topology(name, n, seed, radius))
        .collect()
}

fn build_topologies_for_config(n: usize, config: &KuramotoConfig) -> Result<Vec<Topology>, String> {
    build_topologies(n, &config.topologies, config.seed, config.coupling_radius)?
        .into_iter()
        .map(|topology| {
            let topology = if let Some(seed) = config.topology_relabel_seed {
                relabel_topology(
                    &topology,
                    seed ^ stable_name_seed(&topology.name) ^ n as u64,
                )
            } else {
                topology
            };
            Ok(apply_weight_policy(topology, &config.weight_policy))
        })
        .collect()
}

fn build_topology(
    name: &str,
    n: usize,
    seed: u64,
    radius: Option<usize>,
) -> Result<Topology, String> {
    match name {
        "all_to_all" => Ok(all_to_all_topology(n)),
        "ring" => Ok(ring_topology(n, "ring")),
        "grid" => grid_topology(n),
        "shuffled_ring" => Ok(shuffled_ring_topology(n, seed)),
        TOPO_NONLOCAL_RING => {
            let r = radius.ok_or_else(|| {
                "nonlocal_ring topology requires config.coupling_radius".to_string()
            })?;
            Ok(nonlocal_ring_topology(n, r))
        }
        other => Err(format!("unsupported topology '{}'", other)),
    }
}

// Nonlocal ring (Kuramoto-Sakaguchi chimera substrate): each node couples to its R nearest
// neighbours on EACH side around the ring, uniform weight 1/(2R). Topology is pure data; the same
// kernel runs it. A shuffled variant of this (locality destroyed) is the chimera locality null.
fn nonlocal_ring_topology(n: usize, r: usize) -> Topology {
    let weight = 1.0 / (2 * r) as f64;
    let neighbors = (0..n)
        .map(|i| {
            (1..=r)
                .flat_map(|d| [(i + n - d) % n, (i + d) % n])
                .map(|target| NeighborEdge { target, weight })
                .collect()
        })
        .collect();
    Topology {
        name: TOPO_NONLOCAL_RING.to_string(),
        n,
        weight_policy: format!("nonlocal ring radius R={}, weight=1/(2R)", r),
        neighbors,
    }
}

fn all_to_all_topology(n: usize) -> Topology {
    let weight = 1.0 / n as f64;
    let neighbors = (0..n)
        .map(|i| {
            (0..n)
                .filter(|&j| j != i)
                .map(|j| NeighborEdge { target: j, weight })
                .collect()
        })
        .collect();
    Topology {
        name: "all_to_all".to_string(),
        n,
        weight_policy: "weight=1/N; self edge omitted because sin(0)=0".to_string(),
        neighbors,
    }
}

fn ring_topology(n: usize, name: &str) -> Topology {
    let neighbors = (0..n)
        .map(|i| {
            let mut targets = vec![(i + n - 1) % n, (i + 1) % n];
            targets.sort_unstable();
            targets.dedup();
            targets
                .into_iter()
                .map(|target| NeighborEdge {
                    target,
                    weight: 1.0,
                })
                .collect()
        })
        .collect();
    Topology {
        name: name.to_string(),
        n,
        weight_policy: "ring nearest-neighbor weight=1".to_string(),
        neighbors,
    }
}

fn shuffled_ring_topology(n: usize, seed: u64) -> Topology {
    let perm = shuffled_indices(n, seed ^ 0x9e37_79b9_7f4a_7c15);
    let mut neighbors = vec![Vec::new(); n];
    for pos in 0..n {
        let node = perm[pos];
        let left = perm[(pos + n - 1) % n];
        let right = perm[(pos + 1) % n];
        let mut targets = vec![left, right];
        targets.sort_unstable();
        targets.dedup();
        neighbors[node] = targets
            .into_iter()
            .map(|target| NeighborEdge {
                target,
                weight: 1.0,
            })
            .collect();
    }
    Topology {
        name: "shuffled_ring".to_string(),
        n,
        weight_policy: "degree-preserving deterministic ring relabel; weight=1".to_string(),
        neighbors,
    }
}

fn grid_topology(n: usize) -> Result<Topology, String> {
    let side =
        square_side(n).ok_or_else(|| format!("grid topology requires square N, got {}", n))?;
    let mut neighbors = Vec::with_capacity(n);
    for y in 0..side {
        for x in 0..side {
            let mut targets = vec![
                y * side + ((x + side - 1) % side),
                y * side + ((x + 1) % side),
                ((y + side - 1) % side) * side + x,
                ((y + 1) % side) * side + x,
            ];
            targets.sort_unstable();
            targets.dedup();
            neighbors.push(
                targets
                    .into_iter()
                    .map(|target| NeighborEdge {
                        target,
                        weight: 1.0,
                    })
                    .collect(),
            );
        }
    }
    Ok(Topology {
        name: "grid".to_string(),
        n,
        weight_policy: format!("{}x{} periodic grid 4-neighbor weight=1", side, side),
        neighbors,
    })
}

fn apply_weight_policy(mut topology: Topology, policy: &str) -> Topology {
    if policy == WEIGHT_POLICY_DEGREE_NORMALIZED {
        for edges in &mut topology.neighbors {
            let degree = edges.len();
            if degree > 0 {
                let weight = 1.0 / degree as f64;
                for edge in edges {
                    edge.weight = weight;
                }
            }
        }
        topology.weight_policy = "degree_normalized: each non-empty row sums to 1.0".to_string();
    }
    topology
}

fn square_side(n: usize) -> Option<usize> {
    let side = (n as f64).sqrt() as usize;
    if side * side == n {
        Some(side)
    } else {
        None
    }
}

fn is_square(n: usize) -> bool {
    square_side(n).is_some()
}

fn shuffled_indices(n: usize, seed: u64) -> Vec<usize> {
    let mut out: Vec<usize> = (0..n).collect();
    let mut state = seed;
    for i in (1..n).rev() {
        let j = (splitmix64(&mut state) as usize) % (i + 1);
        out.swap(i, j);
    }
    out
}

fn permute_values<T: Clone>(values: &[T], seed: u64) -> Vec<T> {
    shuffled_indices(values.len(), seed)
        .into_iter()
        .map(|idx| values[idx].clone())
        .collect()
}

fn relabel_topology(topology: &Topology, seed: u64) -> Topology {
    let old_to_new = shuffled_indices(topology.n, seed);
    let mut neighbors = vec![Vec::new(); topology.n];
    for old_node in 0..topology.n {
        let new_node = old_to_new[old_node];
        let mut edges: Vec<NeighborEdge> = topology.neighbors[old_node]
            .iter()
            .map(|edge| NeighborEdge {
                target: old_to_new[edge.target],
                weight: edge.weight,
            })
            .collect();
        edges.sort_by_key(|edge| edge.target);
        neighbors[new_node] = edges;
    }
    Topology {
        name: topology.name.clone(),
        n: topology.n,
        weight_policy: format!(
            "{}; random node-id relabel seed={}",
            topology.weight_policy, seed
        ),
        neighbors,
    }
}

fn stable_name_seed(name: &str) -> u64 {
    name.bytes().fold(0xcbf2_9ce4_8422_2325, |acc, byte| {
        (acc ^ byte as u64).wrapping_mul(0x1000_0000_01b3)
    })
}

fn splitmix64(state: &mut u64) -> u64 {
    *state = state.wrapping_add(0x9e37_79b9_7f4a_7c15);
    let mut z = *state;
    z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
    z ^ (z >> 31)
}

fn wrap_phase(v: f64) -> f64 {
    v.rem_euclid(TWO_PI)
}

fn mean(xs: &[f64]) -> f64 {
    if xs.is_empty() {
        0.0
    } else {
        xs.iter().sum::<f64>() / xs.len() as f64
    }
}

fn mean_u128(xs: &[u128]) -> f64 {
    if xs.is_empty() {
        0.0
    } else {
        xs.iter().sum::<u128>() as f64 / xs.len() as f64
    }
}

fn summarize_u128(xs: &[u128]) -> JsonValue {
    json!({
        "count": xs.len(),
        "min": xs.iter().min().cloned().unwrap_or(0),
        "max": xs.iter().max().cloned().unwrap_or(0),
        "mean": mean_u128(xs)
    })
}

fn summarize_f64(xs: &[f64]) -> JsonValue {
    json!({
        "count": xs.len(),
        "min": xs.iter().cloned().reduce(f64::min).unwrap_or(0.0),
        "max": xs.iter().cloned().reduce(f64::max).unwrap_or(0.0),
        "mean": mean(xs)
    })
}

fn fail_stage(out_dir: &Path, contract: &str, stage: &str, error: String) -> Result<(), String> {
    write_failure(out_dir, contract, stage, &error)?;
    Err(error)
}

fn sha256_file(path: &Path) -> Result<String, String> {
    let bytes = fs::read(path).map_err(|e| format!("failed to read {}: {}", path.display(), e))?;
    Ok(sha256_bytes(&bytes))
}

fn sha256_text(text: &str) -> String {
    sha256_bytes(text.as_bytes())
}

fn sha256_bytes(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    hex::encode(hasher.finalize())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn omega_grid_is_deterministic_and_symmetric() {
        let a = omega_vector(8, 1.0, 10.0);
        let b = omega_vector(8, 1.0, 10.0);
        assert_eq!(a, b);
        for i in 0..4 {
            assert!((a[i] + a[7 - i]).abs() < 1e-12);
        }
    }

    #[test]
    fn order_parameter_distinguishes_sync_from_balanced() {
        assert!((order_parameter(&[0.0, 0.0, 0.0]) - 1.0).abs() < 1e-12);
        let balanced = order_parameter(&[0.0, TWO_PI / 3.0, 2.0 * TWO_PI / 3.0]);
        assert!(balanced < 1e-12);
    }

    // EMERGENCE-DETERMINISTIC-MEASUREMENT-P13: golden-bit lock proving the measurement readout is
    // deterministic BY CONSTRUCTION (it routes through vendored `libm`, already proven cross-arch
    // bit-identical in the determinism wave). Same fixed input ⇒ these exact f64 bits on every target;
    // a `libm`/algorithm change flips the bits → forces a governed review. Mirrors the det_* golden lock.
    #[test]
    fn order_parameter_golden_bits_by_construction() {
        let thetas = [0.1f64, 0.7, 1.3, 2.5, 3.9, 5.1];
        let r = order_parameter(&thetas);
        assert_eq!(
            r.to_bits(),
            0x3fc7dc17ba26b58d,
            "order_parameter golden bits changed (libm surface moved?)"
        );
    }

    #[test]
    fn all_to_all_topology_uses_mean_field_weight() {
        let topology = all_to_all_topology(4);
        assert_eq!(topology.neighbors.len(), 4);
        assert_eq!(topology.neighbors[0].len(), 3);
        assert!(topology.neighbors[0]
            .iter()
            .all(|edge| (edge.weight - 0.25).abs() < 1e-12));
        assert!(!topology.neighbors[0].iter().any(|edge| edge.target == 0));
    }

    #[test]
    fn grid_topology_requires_square_n() {
        assert!(grid_topology(16).is_ok());
        assert!(grid_topology(18).is_err());
    }

    #[test]
    fn deterministic_permutation_preserves_values() {
        let values = vec![0, 1, 2, 3, 4, 5, 6, 7];
        let shuffled = permute_values(&values, 20260623);
        let repeated = permute_values(&values, 20260623);
        assert_eq!(shuffled, repeated);
        assert_ne!(shuffled, values);

        let mut sorted = shuffled;
        sorted.sort_unstable();
        assert_eq!(sorted, values);
    }

    #[test]
    fn relabel_topology_preserves_ring_degree() {
        let topology = ring_topology(8, "ring");
        let relabeled = relabel_topology(&topology, 20260623);
        assert_eq!(relabeled.name, "ring");
        assert_eq!(relabeled.neighbors.len(), topology.neighbors.len());
        assert!(relabeled.neighbors.iter().all(|edges| edges.len() == 2));
        assert!(relabeled
            .neighbors
            .iter()
            .flat_map(|edges| edges.iter())
            .all(|edge| (edge.weight - 1.0).abs() < 1e-12));
    }

    #[test]
    fn degree_normalized_policy_rows_sum_to_one() {
        let config = KuramotoConfig {
            kernel_mode: MODE_NODE_TICK.to_string(),
            topologies: vec![
                "all_to_all".to_string(),
                "ring".to_string(),
                "grid".to_string(),
                "shuffled_ring".to_string(),
            ],
            weight_policy: WEIGHT_POLICY_DEGREE_NORMALIZED.to_string(),
            ..KuramotoConfig::default()
        };
        let topologies = build_topologies_for_config(16, &config).unwrap();
        assert_eq!(topologies.len(), 4);
        for topology in topologies {
            assert_eq!(
                topology.weight_policy,
                "degree_normalized: each non-empty row sums to 1.0"
            );
            for edges in topology.neighbors {
                let row_sum = edges.iter().map(|edge| edge.weight).sum::<f64>();
                assert!((row_sum - 1.0).abs() < 1e-12, "{row_sum}");
            }
        }
    }

    #[test]
    fn provenance_json_shape_is_stable() {
        let prov = build_provenance_json(
            "node_tick",
            "NodeTick",
            Path::new("/lab/kernels/kuramoto_node.ig"),
            "aabbccddeeff0011aabbccddeeff001122334455667788990011223344556677",
            "11ffeeddccbbaa0011ffeeddccbbaa001122334455667788990011223344aabb",
            "0.1.0/igniter-v0",
            "0.1.4",
            None,
        );
        assert_eq!(
            prov["schema"].as_str().unwrap(),
            "igniter.experiment.provenance.v1"
        );
        assert_eq!(
            prov["runner"].as_str().unwrap(),
            "igniter-vm experiment kuramoto"
        );
        assert_eq!(prov["runner_mode"].as_str().unwrap(), "node_tick");
        assert_eq!(prov["entry"].as_str().unwrap(), "NodeTick");
        assert_eq!(
            prov["kernel_digest"].as_str().unwrap(),
            "aabbccddeeff0011aabbccddeeff001122334455667788990011223344556677"
        );
        assert_eq!(
            prov["compiler_version"].as_str().unwrap(),
            "0.1.0/igniter-v0"
        );
        assert_eq!(prov["stdlib_version"].as_str().unwrap(), "0.1.4");
        assert!(prov["artifact_digest"].is_null());
    }

    #[test]
    fn provenance_json_shape_all_to_all_tick() {
        let prov = build_provenance_json(
            "all_to_all_tick",
            "Tick",
            Path::new("/lab/kernels/kuramoto.ig"),
            "deadbeef",
            "cafebabe",
            "0.1.0/igniter-v0",
            "0.1.4",
            None,
        );
        assert_eq!(prov["runner_mode"].as_str().unwrap(), "all_to_all_tick");
        assert_eq!(prov["entry"].as_str().unwrap(), "Tick");
        assert_eq!(
            prov["kernel_source"].as_str().unwrap(),
            "/lab/kernels/kuramoto.ig"
        );
    }

    #[test]
    fn provenance_digests_are_deterministic() {
        let input = "config:{seed:42,gamma:1.0}";
        let h1 = sha256_text(input);
        let h2 = sha256_text(input);
        assert_eq!(h1, h2);
        assert_eq!(h1.len(), 64);
    }

    #[test]
    fn extract_compiler_version_reads_format_and_grammar() {
        let sir = serde_json::json!({
            "format_version": "0.1.0",
            "grammar_version": "igniter-v0",
            "contracts": []
        });
        assert_eq!(extract_compiler_version(&sir), "0.1.0/igniter-v0");
    }

    #[test]
    fn extract_compiler_version_fallback_on_missing_fields() {
        let sir = serde_json::json!({ "contracts": [] });
        assert_eq!(extract_compiler_version(&sir), "unknown/unknown");
    }

    #[test]
    fn shuffled_ring_is_deterministic_degree_two() {
        let a = shuffled_ring_topology(16, 20260622);
        let b = shuffled_ring_topology(16, 20260622);
        assert_eq!(
            serde_json::to_string(&a.neighbors).unwrap(),
            serde_json::to_string(&b.neighbors).unwrap()
        );
        assert!(a.neighbors.iter().all(|edges| edges.len() == 2));
    }
}
