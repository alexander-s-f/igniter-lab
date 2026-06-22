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

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct KuramotoConfig {
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
}

impl Default for KuramotoConfig {
    fn default() -> Self {
        Self {
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
        }
    }
}

fn default_series_stride() -> usize {
    5
}

fn default_cli_sample_ticks() -> usize {
    3
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
    #[serde(rename = "N")]
    n: usize,
    #[serde(rename = "K")]
    k: f64,
    plateau_r: f64,
    expected_r: f64,
    residual: f64,
}

#[derive(Debug)]
struct SimulationResult {
    rows: Vec<SummaryRow>,
    series_rows: Vec<(usize, f64, usize, f64)>,
    dispatch_us: Vec<u128>,
    tick_ms: Vec<f64>,
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
    let mut rows = Vec::new();
    let mut series_rows = Vec::new();
    let mut dispatch_us = Vec::new();
    let mut tick_ms = Vec::new();

    for &n in &config.n_values {
        let omegas = omega_vector(n, config.gamma, config.omega_clip);
        for &k in &config.k_values {
            let mut thetas = init_phases(n);
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
                    series_rows.push((n, k, tick, r));
                }
            }
            let plateau = mean(&r_series[r_series.len() - config.plateau_window..]);
            let expected = expected_r(k, config.kc_expected);
            rows.push(SummaryRow {
                n,
                k,
                plateau_r: plateau,
                expected_r: expected,
                residual: plateau - expected,
            });
        }
    }

    Ok(SimulationResult {
        rows,
        series_rows,
        dispatch_us,
        tick_ms,
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
        .execute(&loaded.bytecode, &inputs, &temporal)
        .await
        .map_err(|e| format!("contract={} error={}", loaded.contract_name, e))?;
    let elapsed = start.elapsed().as_micros();
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
    let n = *config.n_values.first().ok_or("empty n_values")?;
    let k = *config.k_values.last().ok_or("empty k_values")?;
    let sample_ticks = config.cli_sample_ticks.min(config.ticks).max(1);
    let omegas = omega_vector(n, config.gamma, config.omega_clip);
    let mut thetas = init_phases(n);
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

    let config_out = json!({
        "runner": "igniter-vm experiment kuramoto",
        "kernel": args.kernel,
        "entry": args.entry,
        "seed": config.seed,
        "gamma": config.gamma,
        "kc_expected": config.kc_expected,
        "n_values": config.n_values,
        "k_values": config.k_values,
        "dt": config.dt,
        "ticks": config.ticks,
        "plateau_window": config.plateau_window,
        "omega_clip": config.omega_clip,
        "omega_method": "lorentzian_quantile_grid: omega_i = gamma*tan(pi*((i+0.5)/N - 0.5)), clipped",
        "init_phases": "uniform_spread: theta_i = 2*pi*i/N",
        "integrator": "explicit_euler",
        "kernel_sha256": meta.kernel_hash,
        "config_sha256": meta.config_hash,
        "contract_name": loaded.contract_name,
    });
    write_json(args.out_dir.join("config.json"), &config_out)?;

    let mut series = String::from("N,K,tick,r\n");
    for (n, k, tick, r) in &simulation.series_rows {
        series.push_str(&format!("{},{},{},{}\n", n, k, tick, r));
    }
    fs::write(args.out_dir.join("series.csv"), series)
        .map_err(|e| format!("failed to write series.csv: {}", e))?;

    let transition_observed = simulation
        .rows
        .iter()
        .any(|r| r.k >= config.kc_expected * 1.5 && r.plateau_r > 0.4);
    let summary = json!({
        "status": "ok",
        "run_started_utc": meta.run_started.to_rfc3339(),
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
    write_report(args, config, &summary, &timings, speedup)?;
    Ok(())
}

fn write_report(
    args: &ExperimentArgs,
    config: &KuramotoConfig,
    summary: &JsonValue,
    timings: &JsonValue,
    speedup: Option<f64>,
) -> Result<(), String> {
    let mut text = String::new();
    text.push_str("# In-process Kuramoto runner proof\n\n");
    text.push_str("LAB-IGNITER-EXPERIMENT-INPROCESS-RUNNER-P5. Apparatus infrastructure, not a new scientific claim.\n\n");
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
    if let Some(s) = speedup {
        text.push_str(&format!("- CLI/in-process mean ratio: {:.1}x\n", s));
    }
    text.push_str("\n## Summary\n\n```json\n");
    text.push_str(&serde_json::to_string_pretty(summary).unwrap_or_default());
    text.push_str("\n```\n\n");
    text.push_str("## Failure policy\n\nKernel compile/load errors and VM tick errors exit non-zero. Runtime tick failures write `failure.json` with contract/tick/error context before returning failure.\n");
    fs::write(args.out_dir.join("REPORT.md"), text)
        .map_err(|e| format!("failed to write REPORT.md: {}", e))
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

fn init_phases(n: usize) -> Vec<f64> {
    (0..n).map(|i| TWO_PI * i as f64 / n as f64).collect()
}

fn order_parameter(thetas: &[f64]) -> f64 {
    let n = thetas.len() as f64;
    let c = thetas.iter().map(|t| t.cos()).sum::<f64>() / n;
    let s = thetas.iter().map(|t| t.sin()).sum::<f64>() / n;
    (c * c + s * s).sqrt()
}

fn expected_r(k: f64, kc: f64) -> f64 {
    if k > kc {
        (1.0 - kc / k).sqrt()
    } else {
        0.0
    }
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
}
