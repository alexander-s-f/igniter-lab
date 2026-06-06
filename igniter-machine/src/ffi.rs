use crate::fact::Fact;
use crate::machine::IgniterMachine;
use magnus::{prelude::*, Error, RHash, TryConvert, Value};
use std::path::PathBuf;
use std::sync::Arc;

#[magnus::wrap(class = "Igniter::Machine", free_immediately, size)]
pub struct RbMachine {
    pub inner: Arc<IgniterMachine>,
}

impl RbMachine {
    pub fn rb_new(data_dir_val: Value, backend_type: String) -> Result<Self, Error> {
        let data_dir = if data_dir_val.is_nil() {
            None
        } else {
            let dir: String = TryConvert::try_convert(data_dir_val)?;
            Some(PathBuf::from(dir))
        };

        let inner = IgniterMachine::new(data_dir, &backend_type)
            .map_err(|e| Error::new(magnus::exception::runtime_error(), e.to_string()))?;

        Ok(Self {
            inner: Arc::new(inner),
        })
    }

    pub fn rb_load_contract(
        &self,
        source_code: String,
        contract_name: String,
    ) -> Result<(), Error> {
        self.inner
            .load_contract_source(&source_code, &contract_name)
            .map_err(|e| Error::new(magnus::exception::runtime_error(), e.to_string()))
    }

    pub fn rb_dispatch(&self, contract_name: String, inputs_hash: RHash) -> Result<Value, Error> {
        let inputs_json = rb_hash_to_json(inputs_hash)?;

        let out_json =
            futures::executor::block_on(self.inner.dispatch(&contract_name, inputs_json))
                .map_err(|e| Error::new(magnus::exception::runtime_error(), e.to_string()))?;

        json_to_rb_value(out_json)
    }

    pub fn rb_checkpoint(&self, path: String) -> Result<(), Error> {
        self.inner
            .checkpoint(std::path::Path::new(&path))
            .map_err(|e| Error::new(magnus::exception::runtime_error(), e.to_string()))
    }

    pub fn rb_resume_class(
        path: String,
        data_dir_val: Value,
        backend_type: String,
    ) -> Result<Self, Error> {
        let data_dir = if data_dir_val.is_nil() {
            None
        } else {
            let dir: String = TryConvert::try_convert(data_dir_val)?;
            Some(PathBuf::from(dir))
        };

        let inner = IgniterMachine::resume(std::path::Path::new(&path), data_dir, &backend_type)
            .map_err(|e| Error::new(magnus::exception::runtime_error(), e.to_string()))?;

        Ok(Self {
            inner: Arc::new(inner),
        })
    }

    pub fn rb_write_fact(&self, fact_hash: RHash) -> Result<(), Error> {
        let fact_json = rb_hash_to_json(fact_hash)?;
        let fact: Fact = serde_json::from_value(fact_json)
            .map_err(|e| Error::new(magnus::exception::runtime_error(), e.to_string()))?;

        futures::executor::block_on(self.inner.write_fact(fact))
            .map_err(|e| Error::new(magnus::exception::runtime_error(), e.to_string()))
    }

    pub fn rb_read_fact(&self, store: String, key: String, as_of: f64) -> Result<Value, Error> {
        let opt_fact = futures::executor::block_on(self.inner.read_fact(&store, &key, as_of))
            .map_err(|e| Error::new(magnus::exception::runtime_error(), e.to_string()))?;

        match opt_fact {
            Some(fact) => {
                let fact_json = serde_json::to_value(&fact)
                    .map_err(|e| Error::new(magnus::exception::runtime_error(), e.to_string()))?;
                json_to_rb_value(fact_json)
            }
            None => {
                let ruby = magnus::Ruby::get().unwrap();
                Ok(ruby.qnil().as_value())
            }
        }
    }
}

fn rb_hash_to_json(hash: RHash) -> Result<serde_json::Value, Error> {
    let ruby = magnus::Ruby::get().unwrap();
    let json_module = ruby
        .class_object()
        .const_get::<_, magnus::RModule>("JSON")?;
    let dump_val: String = json_module.funcall("dump", (hash,))?;
    let json_val = serde_json::from_str(&dump_val)
        .map_err(|e| Error::new(magnus::exception::runtime_error(), e.to_string()))?;
    Ok(json_val)
}

fn json_to_rb_value(json: serde_json::Value) -> Result<Value, Error> {
    let ruby = magnus::Ruby::get().unwrap();
    let json_module = ruby
        .class_object()
        .const_get::<_, magnus::RModule>("JSON")?;
    let dump_str = serde_json::to_string(&json)
        .map_err(|e| Error::new(magnus::exception::runtime_error(), e.to_string()))?;
    let rb_val: Value = json_module.funcall("parse", (dump_str,))?;
    Ok(rb_val)
}
