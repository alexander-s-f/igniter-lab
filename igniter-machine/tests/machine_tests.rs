use igniter_machine::fact::Fact;
use igniter_machine::machine::IgniterMachine;
use serde_json::json;

#[tokio::test]
async fn test_machine_in_memory_lifecycle() {
    let machine = IgniterMachine::new(None, "in_memory").unwrap();

    let source = "
    module Lang.Examples.Add
    contract Add {
      input  a: Integer
      input  b: Integer
      compute sum = a + b
      output sum: Integer
    }
    ";

    machine.load_contract_source(source, "Add").unwrap();

    let inputs = json!({
        "a": 19,
        "b": 23
    });

    let result = machine.dispatch("Add", inputs).await.unwrap();
    assert_eq!(result, json!(42));
}

#[tokio::test]
async fn test_machine_persistent_rocksdb_lifecycle() {
    let dir =
        std::env::temp_dir().join(format!("igniter_machine_rocksdb_{}", uuid::Uuid::new_v4()));
    let machine = IgniterMachine::new(Some(dir.clone()), "rocksdb").unwrap();

    let fact = Fact {
        id: "fact_1".to_string(),
        store: "accounts".to_string(),
        key: "alice".to_string(),
        value: json!({ "balance": 100 }),
        value_hash: "hash_1".to_string(),
        causation: None,
        transaction_time: 100.0,
        valid_time: Some(100.0),
        schema_version: 1,
        producer: None,
        derivation: None,
    };

    machine.write_fact(fact).await.unwrap();

    let fact_read = machine
        .read_fact("accounts", "alice", 150.0)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(fact_read.value, json!({ "balance": 100 }));

    let machine2 = IgniterMachine::new(Some(dir.clone()), "rocksdb").unwrap();
    let fact_read2 = machine2
        .read_fact("accounts", "alice", 150.0)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(fact_read2.value, json!({ "balance": 100 }));

    let _ = std::fs::remove_dir_all(&dir);
}

#[tokio::test]
async fn test_machine_checkpoint_and_resume() {
    let machine = IgniterMachine::new(None, "in_memory").unwrap();

    let source = "
    module Lang.Examples.Add
    contract Add {
      input  a: Integer
      input  b: Integer
      compute sum = a + b
      output sum: Integer
    }
    ";
    machine.load_contract_source(source, "Add").unwrap();

    let fact = Fact {
        id: "fact_1".to_string(),
        store: "accounts".to_string(),
        key: "bob".to_string(),
        value: json!({ "balance": 200 }),
        value_hash: "hash_1".to_string(),
        causation: None,
        transaction_time: 200.0,
        valid_time: Some(200.0),
        schema_version: 1,
        producer: None,
        derivation: None,
    };
    machine.write_fact(fact).await.unwrap();

    let checkpoint_file = std::env::temp_dir().join(format!("image_{}.igm", uuid::Uuid::new_v4()));
    machine.checkpoint(&checkpoint_file).await.unwrap();

    let machine2 = IgniterMachine::resume(&checkpoint_file, None, "in_memory")
        .await
        .unwrap();

    let inputs = json!({
        "a": 10,
        "b": 20
    });
    let result = machine2.dispatch("Add", inputs).await.unwrap();
    assert_eq!(result, json!(30));

    let fact_read = machine2
        .read_fact("accounts", "bob", 250.0)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(fact_read.value, json!({ "balance": 200 }));

    let _ = std::fs::remove_file(&checkpoint_file);
}

// Verify-by-running: prove the VM-runtime wave (HOF + closures capturing an enclosing
// compute) executes *through the machine* (load_contract_source → dispatch), i.e. the
// fused kernel runs the improved igniter_vm.
#[tokio::test]
async fn test_machine_runs_wave_hof_closures() {
    let machine = IgniterMachine::new(None, "in_memory").unwrap();

    let source = "
    module Lang.Examples.Wave
    contract Wave {
      input  nums: Collection[Integer]
      input  base: Integer
      compute factor = base + 1
      compute scaled = map(nums, n -> n * factor)
      compute big    = filter(scaled, n -> n > base)
      compute total  = count(big)
      output total: Integer
    }
    ";

    machine.load_contract_source(source, "Wave").unwrap();

    // factor=2; scaled=[2,4,6]; big=filter(>1)=[2,4,6]; total=3
    let inputs = json!({ "nums": [1, 2, 3], "base": 1 });
    let result = machine.dispatch("Wave", inputs).await.unwrap();
    assert_eq!(result, json!(3));
}

// Machine-pressure: cross-contract dispatch. An orchestrator calls a helper via
// call_contract. Proves the gap: load registers only the named contract, and dispatch
// builds an empty VM dispatch_table → call_contract can't resolve the callee.
#[tokio::test]
async fn test_machine_cross_contract_dispatch() {
    let machine = IgniterMachine::new(None, "in_memory").unwrap();

    let source = "
    module Lang.Examples.Cross
    pure contract Helper {
      input  x: Integer
      compute doubled = x * 2
      output doubled: Integer
    }
    contract Orchestrator {
      input  n: Integer
      compute result = call_contract(\"Helper\", n)
      output result: Integer
    }
    ";

    machine
        .load_contract_source(source, "Orchestrator")
        .unwrap();
    let inputs = json!({ "n": 5 });
    let result = machine.dispatch("Orchestrator", inputs).await.unwrap();
    assert_eq!(result, json!(10)); // Helper(5) = 10
}

// Machine-pressure: load a REAL multi-file fleet app (modules + imports) through the
// machine and dispatch its cross-contract orchestrator — same result as the CLI.
#[tokio::test]
async fn test_machine_loads_multifile_app() {
    let machine = IgniterMachine::new(None, "in_memory").unwrap();
    let base = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/tests/fixtures/fleet_apps/web_router"
    );
    let paths: Vec<String> = ["example.ig", "serve.ig", "types.ig"]
        .iter()
        .map(|f| format!("{}/{}", base, f))
        .collect();

    machine.load_program(&paths, "RunArticle").unwrap();
    let result = machine.dispatch("RunArticle", json!({})).await.unwrap();
    assert_eq!(result, json!({ "body": "article", "status": 200 }));
}

// Machine-fleet sweep: run every fleet app that the CLI runs green (zero-input
// entrypoint) THROUGH THE MACHINE (load_program + dispatch). Proves machine↔CLI
// parity and catches any machine-specific divergence.
#[tokio::test]
async fn test_machine_fleet_sweep() {
    let apps: &[(&str, &str)] = &[
        ("advanced_logistics", "RunDailyRoutesDemo"),
        ("air_combat", "RunDuel"),
        ("audit_ledger", "BalanceAsOfDay5"),
        ("batch_importer", "RunImport"),
        ("call_router", "RunConnectedMatched"),
        ("erp_logistics", "RunBestRoute"),
        ("igniter_parser", "RunParseDemo"),
        ("job_runner", "RunSuccessSecond"),
        ("lead_router", "RunAccept"),
        ("query_engine", "RunQuery"),
        ("reconciler", "RunReconcileLoop"),
        ("vector_editor", "RunCanvasClickDemo"),
        ("web_router", "RunArticle"),
    ];
    let apps_base = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/fleet_apps");
    let mut failures: Vec<String> = Vec::new();
    let mut ok = 0;
    for (app, entry) in apps {
        let dir = format!("{}/{}", apps_base, app);
        let paths: Vec<String> = std::fs::read_dir(&dir)
            .unwrap()
            .filter_map(|e| e.ok())
            .map(|e| e.path())
            .filter(|p| p.extension().and_then(|x| x.to_str()) == Some("ig"))
            .map(|p| p.to_string_lossy().to_string())
            .collect();
        let machine = IgniterMachine::new(None, "in_memory").unwrap();
        if let Err(e) = machine.load_program(&paths, entry) {
            failures.push(format!("{}: load: {:?}", app, e));
            continue;
        }
        match machine.dispatch(entry, json!({})).await {
            Ok(_) => ok += 1,
            Err(e) => failures.push(format!("{}: dispatch: {:?}", app, e)),
        }
    }
    println!("machine-fleet sweep: {}/{} ok", ok, apps.len());
    assert!(
        failures.is_empty(),
        "machine↔CLI divergence:\n{}",
        failures.join("\n")
    );
}

// Time-travel pressure: write fact versions OUT of transaction_time order, then read
// as-of various boundaries. `latest_for` uses partition_point (requires sorted
// timeline); `push` appends in insertion order → out-of-order writes break as-of.
#[tokio::test]
async fn test_machine_time_travel_out_of_order() {
    let machine = IgniterMachine::new(None, "in_memory").unwrap();
    let mk = |tt: f64, bal: i64| Fact {
        id: format!("f{}", tt as i64),
        store: "acct".to_string(),
        key: "a".to_string(),
        value: json!({ "balance": bal }),
        value_hash: String::new(),
        causation: None,
        transaction_time: tt,
        valid_time: Some(tt),
        schema_version: 1,
        producer: None,
        derivation: None,
    };
    // Insertion order 300, 100, 200 (NOT sorted by transaction_time).
    machine.write_fact(mk(300.0, 30)).await.unwrap();
    machine.write_fact(mk(100.0, 10)).await.unwrap();
    machine.write_fact(mk(200.0, 20)).await.unwrap();

    let bal = |o: Option<Fact>| o.map(|f| f.value);
    assert_eq!(
        bal(machine.read_fact("acct", "a", 50.0).await.unwrap()),
        None,
        "as-of before first → None"
    );
    assert_eq!(
        bal(machine.read_fact("acct", "a", 150.0).await.unwrap()),
        Some(json!({"balance":10})),
        "as-of 150 → tt=100"
    );
    assert_eq!(
        bal(machine.read_fact("acct", "a", 250.0).await.unwrap()),
        Some(json!({"balance":20})),
        "as-of 250 → tt=200"
    );
    assert_eq!(
        bal(machine.read_fact("acct", "a", 350.0).await.unwrap()),
        Some(json!({"balance":30})),
        "as-of 350 → tt=300"
    );
}

// Bitemporal valid-axis (LAB-MACHINE-BITEMPORAL-AXIS-P1 route B): a late CORRECTION —
// same valid_time, later transaction_time. read_bitemporal(valid_at, known_at) must keep
// the axes independent: what was true at valid_at, as best known by known_at.
#[tokio::test]
async fn test_machine_bitemporal_valid_axis() {
    let machine = IgniterMachine::new(None, "in_memory").unwrap();
    let mk = |id: &str, tt: f64, vt: f64, bal: i64| Fact {
        id: id.to_string(),
        store: "acct".to_string(),
        key: "a".to_string(),
        value: json!({ "balance": bal }),
        value_hash: String::new(),
        causation: None,
        transaction_time: tt,
        valid_time: Some(vt),
        schema_version: 1,
        producer: None,
        derivation: None,
    };
    machine.write_fact(mk("f1", 10.0, 10.0, 100)).await.unwrap(); // balance@10 = 100, recorded tt10
    machine.write_fact(mk("f3", 20.0, 20.0, 200)).await.unwrap(); // balance@20 = 200, recorded tt20
    machine.write_fact(mk("f2", 50.0, 10.0, 105)).await.unwrap(); // CORRECTION of balance@10 = 105, recorded tt50

    let bal = |o: Option<Fact>| o.map(|f| f.value);
    // valid@15 known@100: effective at 15 (vt=10), latest correction known by 100 → 105
    assert_eq!(
        bal(machine
            .read_bitemporal("acct", "a", Some(15.0), Some(100.0))
            .await
            .unwrap()),
        Some(json!({"balance":105})),
        "valid@15 known@100"
    );
    // valid@15 known@30: correction (tt50) not yet known → original 100
    assert_eq!(
        bal(machine
            .read_bitemporal("acct", "a", Some(15.0), Some(30.0))
            .await
            .unwrap()),
        Some(json!({"balance":100})),
        "valid@15 known@30 (pre-correction)"
    );
    // valid@25 known@100: effective at 25 = max valid_time<=25 (vt=20) → 200
    assert_eq!(
        bal(machine
            .read_bitemporal("acct", "a", Some(25.0), Some(100.0))
            .await
            .unwrap()),
        Some(json!({"balance":200})),
        "valid@25"
    );
    // valid@5: no version valid that early → None (strict, valid_time=None excluded too)
    assert_eq!(
        bal(machine
            .read_bitemporal("acct", "a", Some(5.0), Some(100.0))
            .await
            .unwrap()),
        None,
        "valid@5 → none"
    );
    // valid_at=None → transaction-time only = latest knowledge (tt50 → 105)
    assert_eq!(
        bal(machine
            .read_bitemporal("acct", "a", None, Some(100.0))
            .await
            .unwrap()),
        Some(json!({"balance":105})),
        "valid_at=None → latest known"
    );
}

// Capsule bytes API (LAB-MACHINE-CAPSULE-MANAGER-P1 step 1): a capsule is an immutable
// frame → checkpoint_bytes must be deterministic and resume_bytes must roundtrip
// byte-identically (so the same frame = the same bytes = content-addressable).
#[tokio::test]
async fn test_machine_checkpoint_bytes_roundtrip() {
    let m = IgniterMachine::new(None, "in_memory").unwrap();
    let src = "
    module M
    contract Add {
      input  a: Integer
      input  b: Integer
      compute sum = a + b
      output sum: Integer
    }
    ";
    m.load_contract_source(src, "Add").unwrap();
    // facts across stores/keys, written OUT of order (stresses the deterministic sort)
    let facts = [
        ("acct", "b", 30.0, 3),
        ("acct", "a", 10.0, 1),
        ("orders", "x", 20.0, 2),
        ("acct", "a", 5.0, 0),
    ];
    for (s, k, tt, v) in facts {
        m.write_fact(Fact {
            id: format!("{}-{}-{}", s, k, tt as i64),
            store: s.to_string(),
            key: k.to_string(),
            value: json!({ "v": v }),
            value_hash: String::new(),
            causation: None,
            transaction_time: tt,
            valid_time: None,
            schema_version: 1,
            producer: None,
            derivation: None,
        })
        .await
        .unwrap();
    }
    let bytes1 = m.checkpoint_bytes().await.unwrap();
    let m2 = IgniterMachine::resume_bytes(&bytes1, None, "in_memory")
        .await
        .unwrap();
    let bytes2 = m2.checkpoint_bytes().await.unwrap();
    assert_eq!(bytes1, bytes2, "capsule byte-identical roundtrip");

    // the resumed frame still dispatches and preserves facts
    assert_eq!(
        m2.dispatch("Add", json!({ "a": 2, "b": 3 })).await.unwrap(),
        json!(5)
    );
    assert_eq!(
        m2.read_fact("acct", "a", 100.0)
            .await
            .unwrap()
            .unwrap()
            .value,
        json!({ "v": 1 })
    );

    // file `.igm` == checkpoint_bytes (the two APIs agree)
    let f = std::env::temp_dir().join(format!("cap_{}.igm", uuid::Uuid::new_v4()));
    m.checkpoint(&f).await.unwrap();
    assert_eq!(
        std::fs::read(&f).unwrap(),
        bytes1,
        "file .igm == checkpoint_bytes"
    );
    let _ = std::fs::remove_file(&f);
}

// Filmstrip proof (LAB-MACHINE-CAPSULE-MANAGER-P1 step 4): one immutable base frame,
// forked into divergent what-if frames; the SAME activation across frames diverges,
// and the base frame is untouched (a fork is a new frame, not a mutation of the past).
#[tokio::test]
async fn test_capsule_filmstrip() {
    use igniter_machine::capsule::CapsuleManager;
    let m = IgniterMachine::new(None, "in_memory").unwrap();
    let src = "
    module M
    contract Add { input a: Integer  input b: Integer  compute sum = a + b  output sum: Integer }
    ";
    m.load_contract_source(src, "Add").unwrap();

    let mut mgr = CapsuleManager::new("in_memory");
    mgr.snapshot("base", &m).await.unwrap(); // frame: Add loaded, no balance fact

    let bal = |v: i64| Fact {
        id: format!("b{}", v),
        store: "acct".to_string(),
        key: "a".to_string(),
        value: json!({ "balance": v }),
        value_hash: String::new(),
        causation: None,
        transaction_time: 1.0,
        valid_time: None,
        schema_version: 1,
        producer: None,
        derivation: None,
    };
    mgr.fork("base", "hi", &[bal(1000)]).await.unwrap();
    mgr.fork("base", "lo", &[bal(10)]).await.unwrap();

    // filmstrip: same activation (read balance) across frames → divergence
    let hi = mgr
        .instantiate("hi")
        .await
        .unwrap()
        .read_fact("acct", "a", 100.0)
        .await
        .unwrap()
        .unwrap();
    let lo = mgr
        .instantiate("lo")
        .await
        .unwrap()
        .read_fact("acct", "a", 100.0)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(hi.value, json!({ "balance": 1000 }));
    assert_eq!(lo.value, json!({ "balance": 10 }));

    // base frame is IMMUTABLE — the forks did not touch it
    assert!(
        mgr.instantiate("base")
            .await
            .unwrap()
            .read_fact("acct", "a", 100.0)
            .await
            .unwrap()
            .is_none(),
        "base frame untouched by forks"
    );

    // dispatch activation works on a resumed frame
    assert_eq!(
        mgr.activate("hi", "Add", json!({ "a": 2, "b": 3 }))
            .await
            .unwrap(),
        json!(5)
    );

    assert_eq!(
        mgr.list(),
        vec!["base".to_string(), "hi".to_string(), "lo".to_string()]
    );
}

// Filmstrip activate_many (LAB-MACHINE-MCP-FILMSTRIP-P1): ONE request over N frames →
// a result table; divergent frames give divergent outputs. Sequential + parallel.
#[tokio::test]
async fn test_capsule_activate_many() {
    use igniter_machine::capsule::CapsuleManager;
    let mut mgr = CapsuleManager::new("in_memory");
    for (cap, val) in [("big", 1000), ("small", 10)] {
        let m = IgniterMachine::new(None, "in_memory").unwrap();
        let src = format!("module M\ncontract V {{ input x: Integer  compute out = x + {}  output out: Integer }}", val);
        m.load_contract_source(&src, "V").unwrap();
        mgr.snapshot(cap, &m).await.unwrap();
    }
    let names = vec!["big".to_string(), "small".to_string()];
    let out = |t: &[serde_json::Value], cap: &str| {
        t.iter().find(|r| r["capsule"] == cap).unwrap()["output"].clone()
    };

    // one request (V, x=0) across both frames → divergence
    let table = mgr
        .activate_many(&names, "V", json!({ "x": 0 }), false)
        .await;
    assert_eq!(table.len(), 2);
    assert_eq!(out(&table, "big"), json!(1000));
    assert_eq!(out(&table, "small"), json!(10));

    // parallel mode → same results (frames immutable, no races)
    let tp = mgr
        .activate_many(&names, "V", json!({ "x": 5 }), true)
        .await;
    assert_eq!(out(&tp, "big"), json!(1005));
    assert_eq!(out(&tp, "small"), json!(15));
}
