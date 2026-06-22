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
//! - One source per `[postgres.read]` section (multi-source deferred).
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
    let capability_id = cfg
        .capability_id
        .as_deref()
        .unwrap_or("IO.PostgresRead")
        .to_string();
    ReadPolicyBinding { policy, capability_id }
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
    crate::read_dispatch::StagedReadHost::new(registry, receipts, &binding.capability_id)
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
            plan.write_policy.allowed_targets.contains(&"todos".to_string()),
            "todos must be an allowed target"
        );
        assert!(
            plan.write_policy.allowed_ops.contains(&"insert".to_string()),
            "insert must be allowed"
        );
        assert!(
            plan.write_policy.allowed_ops.contains(&"upsert".to_string()),
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
            binding.policy.allowed_sources.contains(&"todos".to_string()),
            "todos must be in allowed_sources"
        );
        // fields are allowlisted under the source
        let todos_fields = binding.policy.allowed_fields.get("todos").unwrap();
        for f in ["id", "account_id", "title", "done"] {
            assert!(todos_fields.contains(&f.to_string()), "field {f} must be allowed");
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
            let plan =
                json!({"source": "todos", "projection": ["id", "title"], "limit": 10});
            let req = ServerRequest::new("GET", "/todos", serde_json::Value::Null);
            match host.execute(&plan, &req).await {
                StagedReadResult::Rows(json_str) => {
                    assert!(json_str.contains("Buy milk"), "rows must include seeded row");
                }
                StagedReadResult::Denied(reason) => {
                    panic!("read denied by host policy: {reason}")
                }
                StagedReadResult::HostError(e) => panic!("host error: {e}"),
            }
            assert_eq!(adapter.query_count(), 1, "adapter must have been queried once");
        });
    }
}
