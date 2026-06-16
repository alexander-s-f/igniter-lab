pub mod backend;
pub mod bridge;
pub mod capability;
pub mod capsule;
pub mod clock;
pub mod errors;
pub mod executors;
pub mod fact;
pub mod machine;
pub mod reconcile;
pub mod registry;
pub mod retry;
pub mod retry_queue;
pub mod service_loop;
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
