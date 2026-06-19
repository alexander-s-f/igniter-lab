// tests/reactive_tests.rs
// End-to-end reactive projection pipeline integration tests with tbackend

use igniter_vm::pipeline::ProjectionPipeline;
use igniter_vm::tbackend::LedgerTcpBackend;
use std::collections::HashMap;
use std::process::Command;
use tokio::time::{sleep, Duration};

struct TBackendDaemon {
    child: std::process::Child,
}

impl TBackendDaemon {
    fn new(port: u16) -> Self {
        let binary_path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .unwrap()
            .parent()
            .unwrap()
            .join("runtime/igniter-tbackend/target/release/tbackend");
        let binary_path_str = binary_path.to_str().unwrap();
        let child = Command::new(binary_path_str)
            .arg("--host")
            .arg("127.0.0.1")
            .arg("--port")
            .arg(port.to_string())
            .arg("--data-dir")
            .arg("nil")
            .spawn()
            .expect("Failed to start tbackend daemon");
        Self { child }
    }
}

impl Drop for TBackendDaemon {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

#[tokio::test]
async fn test_reactive_pipeline_integration() {
    let port = 7419;
    let _daemon = TBackendDaemon::new(port);

    // Give it a bit of time to bind the port and start listening
    sleep(Duration::from_millis(500)).await;

    // Connect and verify tbackend is pingable
    let tbackend_addr = format!("127.0.0.1:{}", port);
    let client = LedgerTcpBackend::new(&tbackend_addr);

    // We can ping to be absolutely sure
    let mut online = false;
    for _ in 0..10 {
        if client.ping().await.unwrap_or(false) {
            online = true;
            break;
        }
        sleep(Duration::from_millis(100)).await;
    }
    assert!(online, "TBackend server failed to start within timeout");

    // Initialize ProjectionPipeline
    // Listener port: 8099
    let listener_port = 8099;

    // Let's use the TechnicianBonusCalculator contract JSON
    let contract_json = serde_json::json!({
        "contract_id": "TechnicianBonusCalculator",
        "modifier": "irreversible",
        "inputs": ["technician_id", "as_of"],
        "expression": {
            "kind": "if_expr",
            "condition": {
                "kind": "binary_op",
                "operator": "==",
                "left": {
                    "kind": "temporal_read",
                    "store_ref": "technician_jobs",
                    "as_of_ref": "as_of"
                },
                "right": {
                    "kind": "literal",
                    "value": 5
                }
            },
            "then_branch": {
                "kind": "emit_observation",
                "observation_kind": "bonus_major_selected",
                "expression": {
                    "kind": "literal",
                    "value": 1000
                }
            },
            "else_branch": {
                "kind": "emit_observation",
                "observation_kind": "bonus_minor_selected",
                "expression": {
                    "kind": "literal",
                    "value": 200
                }
            }
        }
    });

    let pipeline = ProjectionPipeline::new(
        contract_json,
        &tbackend_addr,
        listener_port,
        "technician_jobs",
        "computed_bonuses",
    );

    // Start pipeline
    let default_inputs = HashMap::new();
    pipeline
        .start(default_inputs)
        .await
        .expect("Failed to start pipeline");

    // Write a fact of value 5 to technician_jobs store over TCP socket
    let now = chrono::Utc::now().timestamp() as f64;
    let write_req = serde_json::json!({
        "op": "write_fact",
        "fact": {
            "id": uuid::Uuid::new_v4().to_string(),
            "store": "technician_jobs",
            "key": "global",
            "value": 5,
            "value_hash": "test-fact-hash-string",
            "transaction_time": now,
            "valid_time": now,
            "schema_version": 1
        }
    });

    let write_resp = client
        .send_req(write_req)
        .await
        .expect("Failed to write trigger fact");
    assert!(
        write_resp
            .get("ok")
            .and_then(|v| v.as_bool())
            .unwrap_or(false),
        "write_fact failed! Response: {:?}",
        write_resp
    );

    // Wait for the asynchronous out-of-band webhook dispatch and pipeline VM evaluation
    sleep(Duration::from_millis(800)).await;

    // Assert that the computed_bonuses store was automatically updated to 1000 in real time!
    let query_req = serde_json::json!({
        "op": "latest_for",
        "store": "computed_bonuses",
        "key": "global",
        "as_of": now + 10.0
    });

    let query_resp = client
        .send_req(query_req)
        .await
        .expect("Failed to query target store");
    assert!(
        query_resp
            .get("ok")
            .and_then(|v| v.as_bool())
            .unwrap_or(false),
        "Query returned error: {:?}",
        query_resp
    );

    let fact = query_resp
        .get("fact")
        .expect("No fact found in query response");
    assert!(!fact.is_null(), "Fact is null!");
    let val = fact.get("value").expect("No value found in fact");
    assert_eq!(val, &serde_json::json!(1000));

    // Shutdown the pipeline gracefully
    pipeline.shutdown().await.expect("Graceful shutdown failed");
}
