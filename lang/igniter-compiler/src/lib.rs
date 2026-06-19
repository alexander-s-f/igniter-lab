pub mod assembler;
pub mod classifier;
pub mod emitter;
pub mod form_registry;
pub mod form_resolver;
pub mod lexer;
pub mod monomorphizer;
pub mod multifile;
pub mod parser;
pub mod typechecker;
// LAB-IGNITER-WEB-ROUTING-LOWERING-P4: `.igweb` route sugar → explicit `.ig` Serve (lab tooling)
pub mod igweb;
// LAB-COMPILER-PROJECT-MODE-COMPILE-P1: project-root assembly + import closure
pub mod project;
// LAB-COMPILER-LIVENESS-P2: non-fatal instrumentation counters
pub mod liveness;
