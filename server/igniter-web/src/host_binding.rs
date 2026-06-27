//! Host-owned binding layer (LAB-IGNITER-WEB-HOST-CONFIG-EFFECT-BINDINGS-P24).
//!
//! Translates a parsed `HostConfig` into policy + routing structs that the runner can hand to
//! `StagedReadHost` and `MachineEffectHost`. No IO, no env-var access — pure structural
//! transformation from the already-resolved config.
//!
//! Authority boundary:
//! - Policy (source allowlist, field allowlist, target allowlist, ops, row_limit) lives here.
//! - DSN / passport values live in `ResolvedHostConfig` (never logged).
//! - Capsule pool / recipe / `CoordinationHub` are provisioned by the runner, not from config.
//!
//! v0 constraints:
//! - One read DSN; one primary `[postgres.read]` plus optional `[postgres.read.<name>]` extra sources.
//! - `capability_id` defaults if not set in config.
//! - `MachineEffectHost` target→route bindings derived from `[effects.<target>].route`.

use crate::host_config::{HostConfig, PostgresReadConfig, PostgresWriteConfig};
use igniter_machine::postgres_read::PostgresReadPolicy;
use igniter_machine::postgres_write::PostgresWritePolicy;

// ── Write binding ─────────────────────────────────────────────────────────────────────────────────

/// Host-owned write binding: policy + effect-target→route map + capability id.
/// Built from the parsed `HostConfig`; passed to the runner to build `MachineEffectHost`.
pub struct WriteBindingPlan {
    /// `(effect_target, ingress_route)` pairs from `[effects.*]` sections.
    /// Caller does `effect_host.bind_target(target, route)` for each entry.
    pub bind_targets: Vec<(String, String)>,
    /// Allowlist policy for the write executor.
    pub write_policy: PostgresWritePolicy,
    /// Host capability id to register the executor under (e.g. `"IO.TodoWrite"`).
    pub capability_id: String,
}

/// Build a `WriteBindingPlan` from the host config.
/// `bind_targets` always covers every `[effects.*]` entry.
/// `write_policy` and `capability_id` come from `[postgres.write]` (defaults if absent).
pub fn write_binding_plan(cfg: &HostConfig) -> WriteBindingPlan {
    let bind_targets = cfg
        .effects
        .iter()
        .map(|(target, ec)| (target.clone(), ec.route.clone()))
        .collect();

    let (write_policy, capability_id) = if let Some(wc) = &cfg.postgres_write {
        (build_write_policy(wc), write_capability_id(wc))
    } else {
        (PostgresWritePolicy::new(), "IO.HostWrite".to_string())
    };

    WriteBindingPlan {
        bind_targets,
        write_policy,
        capability_id,
    }
}

fn build_write_policy(wc: &PostgresWriteConfig) -> PostgresWritePolicy {
    let mut p = PostgresWritePolicy::new();
    for t in &wc.targets {
        p = p.allow_target(t);
    }
    if !wc.ops.is_empty() {
        p = p.allow_ops(&wc.ops.iter().map(|s| s.as_str()).collect::<Vec<_>>());
    }
    p
}

fn write_capability_id(wc: &PostgresWriteConfig) -> String {
    wc.capability_id
        .as_deref()
        .unwrap_or("IO.HostWrite")
        .to_string()
}

// ── Read binding ──────────────────────────────────────────────────────────────────────────────────

/// Host-owned read policy + capability id.
/// Built from `[postgres.read]`; caller uses it to construct `PostgresReadExecutor` and
/// `StagedReadHost`.
pub struct ReadPolicyBinding {
    pub policy: PostgresReadPolicy,
    /// Host capability id for the read executor (e.g. `"IO.PostgresRead"`).
    pub capability_id: String,
}

/// Build a `ReadPolicyBinding` from the `[postgres.read]` config.
/// `row_limit` clamp and source/field allowlist come from the parsed config.
pub fn read_policy_binding(cfg: &PostgresReadConfig) -> ReadPolicyBinding {
    let mut policy = PostgresReadPolicy::new(cfg.row_limit as i64);
    if let Some(source) = &cfg.source {
        policy = policy.allow_source(
            source,
            &cfg.fields.iter().map(|s| s.as_str()).collect::<Vec<_>>(),
        );
    }
    // Additional `[postgres.read.<name>]` sources (P38) — a two-stage read needs >1 allowlisted table.
    for (source, fields) in &cfg.extra_sources {
        policy = policy.allow_source(
            source,
            &fields.iter().map(|s| s.as_str()).collect::<Vec<_>>(),
        );
    }
    let capability_id = cfg
        .capability_id
        .as_deref()
        .unwrap_or("IO.PostgresRead")
        .to_string();
    ReadPolicyBinding {
        policy,
        capability_id,
    }
}

// ── StagedReadHost factory (machine feature) ──────────────────────────────────────────────────────

/// Build a `StagedReadHost` from a `ReadPolicyBinding` and an adapter (fake or real).
/// The caller owns the adapter; fake adapters are seeded with test rows by the caller.
/// No DSN access — the adapter is already constructed.
#[cfg(feature = "machine")]
pub fn build_staged_read_host_with_adapter<A>(
    binding: &ReadPolicyBinding,
    adapter: std::sync::Arc<A>,
) -> crate::read_dispatch::StagedReadHost
where
    A: igniter_machine::postgres_read::PostgresReadAdapter + 'static,
{
    use igniter_machine::backend::{InMemoryBackend, TBackend};
    use igniter_machine::capability::CapabilityExecutorRegistry;
    use igniter_machine::postgres_read::PostgresReadExecutor;

    let exec = std::sync::Arc::new(PostgresReadExecutor::new(
        &binding.capability_id,
        adapter,
        binding.policy.clone(),
    ));
    let mut registry = CapabilityExecutorRegistry::new();
    registry.register(exec);
    let receipts: std::sync::Arc<dyn TBackend> = std::sync::Arc::new(InMemoryBackend::new());
    // P50: attach the read policy so a TYPED `ReadThen` continuation (e.g. the Todo list's
    // `AccountTodoIndexFromRows : Collection[TodoListRow]`) can derive its `ProjectionSpec` in the runner
    // contour. Without it the typed routing fails closed; the legacy `rows_json` path never needs it.
    crate::read_dispatch::StagedReadHost::new(registry, receipts, &binding.capability_id)
        .with_read_policy(binding.policy.clone())
}

// ── Real Postgres write host factory (postgres feature) ──────────────────────────────────────────

/// Thin bridge decorator that unwraps the `{ intent: <WriteIntent>, correlation_id }` envelope
/// produced by the ingress-capsule step before forwarding to `PostgresWriteExecutor`.
/// The shaping capsule (`ShapeTodoWrite`) re-emits the caller's structured intent as its output;
/// `IngressRouter::handle_effect` wraps that output in `{ intent: <output>, correlation_id }`.
/// This executor lifts `args["intent"]` back to the top level so `PostgresWriteExecutor` sees
/// the raw `WriteIntent` it expects.
#[cfg(feature = "postgres")]
struct IntentBridgeExecutor {
    cap: String,
    inner: igniter_machine::postgres_write::PostgresWriteExecutor<
        igniter_machine::postgres_real::TokioPostgresWriteAdapter,
    >,
}

#[cfg(feature = "postgres")]
#[async_trait::async_trait]
impl igniter_machine::capability::CapabilityExecutor for IntentBridgeExecutor {
    fn capability_id(&self) -> &str {
        &self.cap
    }

    async fn execute(
        &self,
        req: &igniter_machine::capability::EffectRequest,
    ) -> igniter_machine::capability::EffectOutcome {
        let intent = req
            .args
            .get("intent")
            .cloned()
            .unwrap_or_else(|| req.args.clone());
        self.inner
            .execute(&igniter_machine::capability::EffectRequest {
                capability_id: req.capability_id.clone(),
                idempotency_key: req.idempotency_key.clone(),
                authority_ref: req.authority_ref.clone(),
                args: intent,
            })
            .await
    }
}

/// All host-owned components needed to drive a real `MachineEffectHost` for Postgres writes.
/// Built by `build_write_host_from_resolved`; the caller derives `EffectBridgeConfig` and
/// `MachineEffectHost` from references to this struct (both borrow `'_` from it).
#[cfg(feature = "postgres")]
pub struct WriteHostComponents {
    pub hub: igniter_machine::coordination::CoordinationHub,
    pub router: igniter_machine::ingress::IngressRouter,
    pub registry: igniter_machine::capability::CapabilityExecutorRegistry,
    pub receipts: std::sync::Arc<dyn igniter_machine::backend::TBackend>,
    pub clk: std::sync::Arc<dyn igniter_machine::clock::ClockProvider>,
    pub ep: igniter_machine::capability::CapabilityPassport,
    pub effect_verifier: igniter_machine::capability::PassportVerifier,
    pub sf: igniter_machine::single_flight::SingleFlight,
    pub capability_id: String,
    pub bind_targets: Vec<(String, String)>,
}

#[cfg(feature = "postgres")]
fn host_process_effect_signing_key() -> [u8; 32] {
    let material = format!(
        "igweb-effect-host|pid:{}|nanos:{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos()
    );
    *blake3::hash(material.as_bytes()).as_bytes()
}

#[cfg(feature = "postgres")]
fn signed_passport(
    key: &[u8; 32],
    subject: &str,
    capability_id: &str,
    scopes: Vec<String>,
) -> igniter_machine::capability::CapabilityPassport {
    let mut passport = igniter_machine::capability::CapabilityPassport {
        subject: subject.to_string(),
        capability_id: capability_id.to_string(),
        scopes,
        issued_at: 0.0,
        expires_at: Some(f64::MAX),
        revoked: false,
        evidence_digest: String::new(),
    };
    passport.evidence_digest = igniter_machine::capability::sign_passport(key, &passport);
    passport
}

/// Build all host-owned write infrastructure from the resolved host config.
///
/// Returns `Ok(None)` when:
/// - no `[postgres.write]` section, or
/// - no `[effects.*]` sections, or
/// - no `[effects.*]` section carries a resolved `passport_env` value (no bearer auth = no write path).
///
/// Returns `Err` when the section is present and configured but connection or coordination setup
/// fails — caller should abort before binding the socket.
///
/// v0 constraint: single `targets[0]` entry; multi-target requires a separate card.
#[cfg(feature = "postgres")]
pub async fn build_write_host_from_resolved(
    cfg: &HostConfig,
    resolved: &crate::host_config::ResolvedHostConfig,
) -> Result<Option<WriteHostComponents>, Box<dyn std::error::Error + Send + Sync>> {
    use igniter_machine::{
        backend::{InMemoryBackend, TBackend},
        capability::{CapabilityExecutorRegistry, PassportVerifier},
        clock::{ClockProvider, SystemClock},
        coordination::{
            AgentIdentity, AgentKind, AgentStatus, COORDINATION_CAPABILITY, CoordinationHub,
            DuplicatePolicy, PoolRight, PoolVisibility, ServiceRecipe,
        },
        ingress::IngressRouter,
        machine::IgniterMachine,
        postgres_real::TokioPostgresWriteAdapter,
        postgres_write::PostgresWriteExecutor,
        single_flight::SingleFlight,
    };
    use std::sync::Arc;

    let wc = match &cfg.postgres_write {
        Some(wc) => wc,
        None => return Ok(None),
    };
    // Collect resolved bearer tokens from effects that have passport_env set.
    // Each token is the value the vendor HTTP client sends in Authorization: Bearer <token>.
    let bearer_tokens: Vec<String> = resolved
        .effects
        .values()
        .filter_map(|re| re.passport.clone())
        .collect::<std::collections::HashSet<_>>()
        .into_iter()
        .collect();
    if bearer_tokens.is_empty() {
        // No authenticated effects → no write path to wire. Fall-closed.
        return Ok(None);
    }
    let dsn = match &resolved.postgres_write_dsn {
        Some(d) => d.as_str(),
        None => return Ok(None),
    };

    // v0: single write target from config (multi-target = future card).
    let target = wc.targets.first().map(|s| s.as_str()).unwrap_or("todos");
    let key_col = wc.key_column.as_deref().unwrap_or("id");
    let col_refs: Vec<&str> = wc.columns.iter().map(|s| s.as_str()).collect();
    let adapter =
        Arc::new(TokioPostgresWriteAdapter::connect(dsn, target, key_col, &col_refs).await?);

    let plan = write_binding_plan(cfg);
    let capability_id = plan.capability_id.clone();

    // Build executor: IntentBridgeExecutor wraps PostgresWriteExecutor to lift the capsule's
    // bridge envelope (args["intent"]) before write policy enforcement.
    let inner = PostgresWriteExecutor::new(&capability_id, adapter, plan.write_policy.clone());
    let exec: Arc<dyn igniter_machine::capability::CapabilityExecutor> =
        Arc::new(IntentBridgeExecutor {
            cap: capability_id.clone(),
            inner,
        });
    let mut registry = CapabilityExecutorRegistry::new();
    registry.register(exec);

    // ── Coordination infrastructure ─────────────────────────────────────────────────────────────
    // Matches the proven P9/P11 test shape: 3 shaping-capsule replicas, dedup_strict recipe,
    // one route "/w" → pool "svc", bearer tokens → coordination passport.

    let clk: Arc<dyn ClockProvider> = Arc::new(SystemClock);
    let audit: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    let signing_key = host_process_effect_signing_key();
    let verifier = PassportVerifier::new().trust(signing_key);
    let mut hub =
        CoordinationHub::new_signed(Arc::clone(&audit), Arc::clone(&clk), verifier.clone());

    // Host-internal coordination subjects (never product-named; purely infra).
    let actor_id = "host:write-actor";
    let dev_id = "host:dev";
    let svc_id = "host:svc";

    let coord_passport = signed_passport(
        &signing_key,
        svc_id,
        COORDINATION_CAPABILITY,
        vec![
            "create_pool".into(),
            "import_capsule".into(),
            "activate_capsule".into(),
            "grant_access".into(),
            "accept_recipe".into(),
            "invoke".into(),
        ],
    );
    let dev_passport = signed_passport(
        &signing_key,
        dev_id,
        COORDINATION_CAPABILITY,
        vec!["accept_recipe".into(), "grant_access".into()],
    );

    hub.register_agent(AgentIdentity {
        agent_id: actor_id.into(),
        kind: AgentKind::Agent,
        label: actor_id.into(),
        status: AgentStatus::Active,
        registered_at: 0.0,
    })
    .await?;
    hub.register_agent(AgentIdentity {
        agent_id: dev_id.into(),
        kind: AgentKind::Developer,
        label: dev_id.into(),
        status: AgentStatus::Active,
        registered_at: 0.0,
    })
    .await?;
    hub.register_agent(AgentIdentity {
        agent_id: svc_id.into(),
        kind: AgentKind::RuntimeActor,
        label: svc_id.into(),
        status: AgentStatus::Active,
        registered_at: 0.0,
    })
    .await?;

    hub.create_pool(&coord_passport, "svc", "candidate", PoolVisibility::Private)
        .await
        .map_err(|e| e.reason())?;

    // ShapeTodoWrite shaping capsule: re-emits the structured WriteIntent as capsule output so the
    // bridge envelope wraps it as { intent: <WriteIntent>, correlation_id }.
    let capsule_src = "contract ShapeTodoWrite {\n\
        input operation : String\n  input target : String\n  input key : String\n\
        input values : Unknown\n  input correlation_id : String\n\
        compute intent = { operation: operation, target: target, key: key, \
        values: values, correlation_id: correlation_id }\n\
        output intent : Unknown\n}";
    let m = IgniterMachine::new(None, "in_memory")?;
    m.load_contract_source(capsule_src, "ShapeTodoWrite")?;
    let bytes = m.checkpoint_bytes().await?;

    let mut digest = String::new();
    for _ in 0..3 {
        digest = hub
            .add_capsule(&coord_passport, "svc", bytes.clone(), vec![])
            .await
            .map_err(|e| e.reason())?
            .capsule_id;
    }

    let dup_policy = DuplicatePolicy {
        mode: "dedup_strict".into(),
        key_header: "idempotency-key".into(),
        max_fresh: 0,
        after_limit: "dedup_last".into(),
        seed_field: "attempt".into(),
        variant_payload: false,
        require_key: true,
    };
    hub.accept_recipe(
        &dev_passport,
        "svc",
        ServiceRecipe {
            recipe_id: "host-write-r1".into(),
            capsule_digest: digest,
            entry_contract: "ShapeTodoWrite".into(),
            input_schema_digest: None,
            capability_bindings: vec![],
            required_scopes: vec!["invoke".into()],
            receipt_policy: "audit".into(),
            retry_policy_ref: None,
            pool_sizing: 3,
            created_by: actor_id.into(),
            accepted_by: None,
            accepted_at: None,
            duplicate_policy: Some(dup_policy),
        },
    )
    .await
    .map_err(|e| e.reason())?;

    hub.grant(&dev_passport, "svc", svc_id, PoolRight::ActivateCapsule)
        .await
        .map_err(|e| e.reason())?;

    // Wire ingress router: all effects route to pool "svc" via "/w".
    // Each unique resolved bearer token is registered against the coordination passport
    // (the token value comes from `passport_env` in host.toml; clients send it as Bearer).
    let mut router = IngressRouter::new();
    router.route("/w", "svc");
    for token in &bearer_tokens {
        router.token(token, coord_passport.clone());
    }

    let ep = signed_passport(&signing_key, "host", &capability_id, vec!["write".into()]);

    Ok(Some(WriteHostComponents {
        hub,
        router,
        registry,
        receipts: Arc::new(InMemoryBackend::new()),
        clk,
        ep,
        effect_verifier: verifier,
        sf: SingleFlight::new(),
        capability_id,
        bind_targets: plan.bind_targets,
    }))
}

// ── Real Postgres read host factory (postgres feature) ───────────────────────────────────────────

/// Build a `StagedReadHost` backed by a real `TokioPostgresReadAdapter`.
///
/// Called by the binary under `--features postgres`; tests use the same function to prove the
/// binary's construction path.  Returns `Ok(None)` when `[postgres.read]` is absent — the caller
/// keeps its fail-closed empty host.  Returns `Err` when the section is present but the connection
/// fails (caller should abort before binding the socket).
#[cfg(feature = "postgres")]
pub async fn build_staged_read_host_from_resolved(
    cfg: &HostConfig,
    resolved: &crate::host_config::ResolvedHostConfig,
) -> Result<Option<crate::read_dispatch::StagedReadHost>, Box<dyn std::error::Error + Send + Sync>>
{
    let rc = match &cfg.postgres_read {
        Some(rc) => rc,
        None => return Ok(None),
    };
    let dsn = match &resolved.postgres_read_dsn {
        Some(d) => d.as_str(),
        None => return Ok(None),
    };
    use igniter_machine::postgres_real::TokioPostgresReadAdapter;
    let adapter = TokioPostgresReadAdapter::connect(dsn).await?;
    let binding = read_policy_binding(rc);
    Ok(Some(build_staged_read_host_with_adapter(
        &binding,
        std::sync::Arc::new(adapter),
    )))
}

// ── tests ─────────────────────────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::host_config::parse_host_config;

    // ── write binding ─────────────────────────────────────────────────────────────────────────────

    #[test]
    fn write_binding_plan_derives_targets_and_ops() {
        let cfg = parse_host_config(
            "[postgres.write]\ndsn_env = \"W\"\ntargets = \"todos\"\nops = \"insert,upsert\"\n\
             capability = \"IO.TodoWrite\"\n",
        )
        .unwrap();
        let plan = write_binding_plan(&cfg);
        assert_eq!(plan.capability_id, "IO.TodoWrite");
        assert!(
            plan.write_policy
                .allowed_targets
                .contains(&"todos".to_string()),
            "todos must be an allowed target"
        );
        assert!(
            plan.write_policy
                .allowed_ops
                .contains(&"insert".to_string()),
            "insert must be allowed"
        );
        assert!(
            plan.write_policy
                .allowed_ops
                .contains(&"upsert".to_string()),
            "upsert must be allowed"
        );
    }

    #[test]
    fn write_binding_plan_derives_bind_targets_from_effects() {
        let cfg = parse_host_config(
            "[effects.todo-create]\nroute = \"/w\"\n[effects.todo-done]\nroute = \"/w\"\n\
             [postgres.write]\ndsn_env = \"W\"\n",
        )
        .unwrap();
        let plan = write_binding_plan(&cfg);
        let mut targets: Vec<_> = plan.bind_targets.iter().map(|(t, _)| t.as_str()).collect();
        targets.sort();
        assert_eq!(targets, vec!["todo-create", "todo-done"]);
        for (_, route) in &plan.bind_targets {
            assert_eq!(route, "/w");
        }
    }

    #[test]
    fn write_binding_plan_no_postgres_write_section_has_empty_policy() {
        let cfg = parse_host_config("[effects.x]\nroute = \"/w\"\n").unwrap();
        let plan = write_binding_plan(&cfg);
        assert_eq!(plan.capability_id, "IO.HostWrite");
        assert!(plan.write_policy.allowed_targets.is_empty());
    }

    #[test]
    fn write_binding_plan_default_capability_id() {
        let cfg =
            parse_host_config("[postgres.write]\ndsn_env = \"W\"\ntargets = \"todos\"\n").unwrap();
        let plan = write_binding_plan(&cfg);
        assert_eq!(plan.capability_id, "IO.HostWrite");
    }

    // ── read binding ──────────────────────────────────────────────────────────────────────────────

    #[test]
    fn read_policy_binding_allows_source_and_fields() {
        let cfg = parse_host_config(
            "[postgres.read]\ndsn_env = \"R\"\nsource = \"todos\"\n\
             fields = \"id,account_id,title,done\"\nrow_limit = \"50\"\n\
             capability = \"IO.PostgresRead\"\n",
        )
        .unwrap();
        let rc = cfg.postgres_read.as_ref().unwrap();
        let binding = read_policy_binding(rc);
        assert_eq!(binding.capability_id, "IO.PostgresRead");
        // row_limit clamp is set
        assert_eq!(binding.policy.row_limit, 50);
        // source is allowlisted
        assert!(
            binding
                .policy
                .allowed_sources
                .contains(&"todos".to_string()),
            "todos must be in allowed_sources"
        );
        // fields are allowlisted under the source
        let todos_fields = binding.policy.allowed_fields.get("todos").unwrap();
        for f in ["id", "account_id", "title", "done"] {
            assert!(
                todos_fields.contains(&f.to_string()),
                "field {f} must be allowed"
            );
        }
    }

    #[test]
    fn read_policy_binding_default_capability_id() {
        let cfg = parse_host_config("[postgres.read]\ndsn_env = \"R\"\n").unwrap();
        let rc = cfg.postgres_read.as_ref().unwrap();
        let binding = read_policy_binding(rc);
        assert_eq!(binding.capability_id, "IO.PostgresRead");
    }

    #[test]
    fn read_policy_binding_no_source_allows_nothing() {
        let cfg = parse_host_config("[postgres.read]\ndsn_env = \"R\"\n").unwrap();
        let rc = cfg.postgres_read.as_ref().unwrap();
        let binding = read_policy_binding(rc);
        assert!(binding.policy.allowed_sources.is_empty());
    }

    #[test]
    fn read_policy_binding_row_limit_default_100() {
        let cfg = parse_host_config("[postgres.read]\ndsn_env = \"R\"\n").unwrap();
        let rc = cfg.postgres_read.as_ref().unwrap();
        let binding = read_policy_binding(rc);
        assert_eq!(binding.policy.row_limit, 100);
    }

    // ── StagedReadHost factory (machine feature) ──────────────────────────────────────────────────

    // ── StagedReadHost factory (machine feature) ──────────────────────────────────────────────────

    #[cfg(feature = "machine")]
    #[test]
    fn build_staged_read_host_denied_field_before_adapter() {
        // Proves: host field allowlist is enforced BEFORE the adapter is ever called.
        // Policy allows only "id" and "title"; a plan requesting "done" is denied at (G3).
        use igniter_machine::postgres_read::FakePostgresAdapter;
        use serde_json::json;
        use std::sync::Arc;

        let cfg = parse_host_config(
            "[postgres.read]\ndsn_env = \"R\"\nsource = \"todos\"\n\
             fields = \"id,title\"\nrow_limit = \"10\"\n",
        )
        .unwrap();
        let rc = cfg.postgres_read.as_ref().unwrap();
        let binding = read_policy_binding(rc);

        let adapter = Arc::new(
            FakePostgresAdapter::new()
                .with_table("todos", vec![json!({"id": "t1", "title": "Buy milk"})]),
        );
        let host = build_staged_read_host_with_adapter(&binding, adapter.clone());

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        rt.block_on(async {
            use crate::read_dispatch::StagedReadResult;
            use igniter_server::protocol::ServerRequest;
            // "done" is not in the allowlist (id, title only) — host gate fires before adapter.
            let plan =
                json!({"source": "todos", "projection": ["id", "title", "done"], "limit": 10});
            let req = ServerRequest::new("GET", "/todos", serde_json::Value::Null);
            match host.execute(&plan, &req).await {
                // StagedReadResult::Denied carries the generic host message; the detail
                // ("forbidden field: done") is in EffectOutcome.result["denied"] — not leaked.
                StagedReadResult::Denied(_) => {}
                StagedReadResult::Rows(_) => panic!("should be denied for forbidden field"),
                StagedReadResult::HostError(e) => panic!("unexpected host error: {e}"),
            }
            assert_eq!(
                adapter.query_count(),
                0,
                "adapter must NOT be reached when field is denied before query"
            );
        });
    }

    #[cfg(feature = "machine")]
    #[test]
    fn build_staged_read_host_executes_fake_query() {
        use igniter_machine::postgres_read::FakePostgresAdapter;
        use serde_json::json;
        use std::sync::Arc;

        let cfg = parse_host_config(
            "[postgres.read]\ndsn_env = \"R\"\nsource = \"todos\"\n\
             fields = \"id,title\"\nrow_limit = \"10\"\n",
        )
        .unwrap();
        let rc = cfg.postgres_read.as_ref().unwrap();
        let binding = read_policy_binding(rc);

        let adapter = Arc::new(
            FakePostgresAdapter::new()
                .with_table("todos", vec![json!({"id": "t1", "title": "Buy milk"})]),
        );
        let host = build_staged_read_host_with_adapter(&binding, adapter.clone());

        // Execute a read through the staged host — no socket needed.
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        rt.block_on(async {
            use crate::read_dispatch::StagedReadResult;
            use igniter_server::protocol::ServerRequest;
            let plan = json!({"source": "todos", "projection": ["id", "title"], "limit": 10});
            let req = ServerRequest::new("GET", "/todos", serde_json::Value::Null);
            match host.execute(&plan, &req).await {
                StagedReadResult::Rows(json_str) => {
                    assert!(
                        json_str.contains("Buy milk"),
                        "rows must include seeded row"
                    );
                }
                StagedReadResult::Denied(reason) => {
                    panic!("read denied by host policy: {reason}")
                }
                StagedReadResult::HostError(e) => panic!("host error: {e}"),
            }
            assert_eq!(
                adapter.query_count(),
                1,
                "adapter must have been queried once"
            );
        });
    }
}
