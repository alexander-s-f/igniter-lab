mod commands;
use commands::MachineState;
use igniter_machine::machine::IgniterMachine;
use parking_lot::Mutex;
use std::sync::Arc;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let machine = IgniterMachine::new(None, "in_memory")
        .expect("Failed to initialize Igniter Machine");

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .manage(MachineState(Arc::new(Mutex::new(machine))))
        .manage(commands::TelemetryHistoryState(Mutex::new(Vec::new())))
        .register_uri_scheme_protocol("igniter-proof", |_ctx, request| {
            let path = request.uri().path();
            if path == "/" || path == "/index.html" {
                let ssr_path = commands::resolve_workspace_path("igniter-view-engine/out/tabs_ssr_output.html");
                let ssr_content = std::fs::read_to_string(&ssr_path)
                    .unwrap_or_else(|e| format!("Error loading SSR output from {:?}: {}", ssr_path, e));

                let html = format!(r#"<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Igniter IVF Proof Window</title>
  <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'self' 'unsafe-inline' igniter-proof:; style-src 'self' 'unsafe-inline';">
  <style>
    :root {{
      --bg-ink-1: #121214;
      --bg-ink-2: #1a1a1e;
      --line: #2d2d34;
      --ignite: #ff6a3d;
      --grey: #8a8a93;
      --grey-2: #c4c4c7;
      --oof: #ff453a;
      --text-ink-1: #e7ddd2;
    }}
    body {{
      background-color: var(--bg-ink-1);
      color: var(--text-ink-1);
      font-family: ui-sans-serif, system-ui, sans-serif;
      margin: 0;
      padding: 40px;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      box-sizing: border-box;
    }}
    .proof-container {{
      width: 100%;
      max-width: 640px;
    }}
    h1 {{
      font-size: 1.5rem;
      margin-bottom: 20px;
      font-weight: 700;
      color: var(--text-ink-1);
      text-align: center;
    }}
    .tabs-component {{
      background-color: var(--bg-ink-2);
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 24px;
      box-shadow: 0 4px 20px rgba(0, 0, 0, 0.4);
    }}
    .tabs-list {{
      display: flex;
      gap: 8px;
      border-bottom: 1px solid var(--line);
      padding-bottom: 8px;
    }}
    .tab-btn {{
      background: none;
      border: none;
      color: var(--grey);
      font-family: monospace;
      font-size: 12px;
      padding: 8px 16px;
      cursor: pointer;
      border-radius: 4px 4px 0 0;
      transition: color 0.15s, background-color 0.15s;
    }}
    .tab-btn:hover {{
      color: var(--grey-2);
    }}
    .tab-btn[aria-selected="true"] {{
      background-color: var(--ignite);
      color: var(--bg-ink-1);
      font-weight: bold;
    }}
    .tab-panel {{
      padding: 16px;
      background-color: var(--bg-ink-1);
      border: 1px solid var(--line);
      border-radius: 4px;
      margin-top: 8px;
      font-size: 13px;
    }}
    .warning-banner {{
      font-size: 12px;
      font-family: monospace;
      padding: 8px 12px;
      border-radius: 4px;
      margin-top: 12px;
    }}
    .warning-banner.block {{
      display: block;
      border: 1px solid var(--oof);
      background-color: rgba(255, 69, 58, 0.05);
      color: var(--oof);
    }}
    .hidden {{
      display: none !important;
    }}
    .block {{
      display: block !important;
    }}
    .proof-footer {{
      margin-top: 24px;
      font-size: 10px;
      color: var(--grey);
      text-align: center;
      font-family: monospace;
    }}
  </style>
</head>
<body>
  <div class="proof-container">
    <h1>Igniter IVF Proof Window</h1>

    <!-- SSR HTML Content -->
    {}

    <div class="proof-footer">
      Status: lab-only �� no-canon �� no-public-framework
    </div>
  </div>

  <!-- Hydration Micro-Runtime -->
  <script src="igniter-proof://localhost/assets/igniter_view_runtime.js"></script>
</body>
</html>"#, ssr_content);

                tauri::http::Response::builder()
                    .header(tauri::http::header::CONTENT_TYPE, "text/html")
                    .header("Content-Security-Policy", "default-src 'none'; script-src 'self' 'unsafe-inline' igniter-proof:; style-src 'self' 'unsafe-inline';")
                    .status(200)
                    .body(html.into_bytes())
                    .unwrap()
            } else if path == "/assets/igniter_view_runtime.js" || path == "/igniter_view_runtime.js" {
                let js_path = commands::resolve_workspace_path("igniter-view-engine/igniter_view_runtime.js");
                let js_content = std::fs::read(&js_path)
                    .unwrap_or_default();
                tauri::http::Response::builder()
                    .header(tauri::http::header::CONTENT_TYPE, "application/javascript")
                    .status(200)
                    .body(js_content)
                    .unwrap()
            } else {
                tauri::http::Response::builder()
                    .status(404)
                    .body(Vec::new())
                    .unwrap()
            }
        })
        .setup(|app| {
            let _window = tauri::WebviewWindowBuilder::new(
                app,
                "proof-window",
                tauri::WebviewUrl::CustomProtocol("igniter-proof://localhost/".parse().unwrap())
            )
            .title("Igniter IVF Proof Window")
            .inner_size(800.0, 600.0)
            .build()
            .unwrap();
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::load_contract,
            commands::load_contract_from_file,
            commands::dispatch_contract,
            commands::list_contracts,
            commands::write_fact,
            commands::read_facts,
            commands::list_observations,
            commands::checkpoint_machine,
            commands::resume_machine,
            commands::get_status,
            commands::clear_observations,
            commands::get_contract_ir,
            commands::open_workspace,
            commands::create_workspace,
            commands::list_ig_files,
            commands::read_file,
            commands::write_file,
            commands::load_workspace_contracts,
            commands::check_source,
            commands::get_system_graph,
            commands::dispatch_traced,
            commands::create_app,
            commands::list_apps,
            commands::list_dir_tree,
            commands::create_file,
            commands::delete_file,
            commands::rename_file,
            commands::inject_slot_values,
            commands::simulate_trace_observation,
            commands::play_trace_playback,
            commands::record_trigger_intent,
            commands::read_playback_receipt,
            commands::simulate_vm_trace_adapter,
            commands::get_telemetry_history,
            commands::ingest_external_trace_event,
            commands::ingest_adapted_vm_trace,
            commands::run_mock_vm_runner_dispatch,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
