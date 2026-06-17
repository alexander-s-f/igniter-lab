pub mod backend;
pub mod bridge;
pub mod bridge_effect;
pub mod capability;
pub mod capsule;
pub mod clock;
pub mod compensation;
pub mod coordination;
pub mod correlation;
pub mod errors;
pub mod executors;
pub mod fact;
pub mod frame_binding;
pub mod frame_binding_effect;
pub mod http;
pub mod ingress;
pub mod machine;
pub mod observability;
pub mod orchestrator;
pub mod postgres_read;
pub mod postgres_write;
pub mod reconcile;
pub mod recovery;
pub mod registry;
pub mod secrets;
pub mod retry;
pub mod retry_queue;
pub mod service_loop;
pub mod serving_loop;
pub mod single_flight;
pub mod sparkcrm;
pub mod write;
pub mod wal;

#[cfg(feature = "ffi")]
pub mod ffi;

#[cfg(feature = "ffi")]
use ffi::RbMachine;
#[cfg(feature = "ffi")]
use magnus::{function, method, prelude::*, Error, Ruby};

#[cfg(feature = "ffi")]
#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    ruby.require("json")?;

    let igniter = ruby.define_module("Igniter")?;
    let machine_class = igniter.define_class("Machine", ruby.class_object())?;

    machine_class.define_singleton_method("new", function!(RbMachine::rb_new, 2))?;
    machine_class.define_singleton_method("resume", function!(RbMachine::rb_resume_class, 3))?;
    machine_class.define_method("load_contract", method!(RbMachine::rb_load_contract, 2))?;
    machine_class.define_method("dispatch", method!(RbMachine::rb_dispatch, 2))?;
    machine_class.define_method("checkpoint", method!(RbMachine::rb_checkpoint, 1))?;
    machine_class.define_method("write_fact", method!(RbMachine::rb_write_fact, 1))?;
    machine_class.define_method("read_fact", method!(RbMachine::rb_read_fact, 3))?;

    Ok(())
}
