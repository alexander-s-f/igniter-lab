pub mod lexer;
pub mod parser;
pub mod classifier;
pub mod typechecker;
pub mod form_registry;
pub mod form_resolver;
pub mod emitter;
pub mod assembler;
pub mod monomorphizer;
pub mod multifile;
// LAB-COMPILER-PROJECT-MODE-COMPILE-P1: project-root assembly + import closure
pub mod project;
// LAB-COMPILER-LIVENESS-P2: non-fatal instrumentation counters
pub mod liveness;
