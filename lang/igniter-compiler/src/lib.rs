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

/// LAB-IGNITER-PACKAGE-STDLIB-VERSION-CONSTANT-P6
/// The version of the stdlib **contract surface this compiler implements** (the baked-in `stdlib.*`
/// signatures in `typechecker::stdlib_calls`). `igniter-stdlib` is not a Cargo dependency of the compiler,
/// so this constant is the authoritative, compiler-owned stdlib version — mirrored from
/// `igniter-stdlib/Cargo.toml` and guarded by a test (`stdlib_version_mirrors_crate`) against silent
/// divergence. Bump this when the baked-in stdlib surface changes.
pub const STDLIB_VERSION: &str = "0.1.4";
