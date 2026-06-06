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
    machine.checkpoint(&checkpoint_file).unwrap();

    let machine2 = IgniterMachine::resume(&checkpoint_file, None, "in_memory").unwrap();

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
