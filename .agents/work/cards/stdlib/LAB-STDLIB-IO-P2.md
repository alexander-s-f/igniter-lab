Card: LAB-STDLIB-IO-P2
Agent: [Implementation Agent]
Role: implementation-agent
Track: lab-experimental-io-capability-effect-surface-proof-v0
Route: EXPERIMENTAL / LAB-ONLY
Status: done

[D] Decisions
- Added body-level keywords `capability` and `effect` to allow explicit side-effect declaration at the contract language boundary.
- Enforced strict compiler-time classification that maps all capability-gated node expressions containing `stdlib.IO.*` to the `"escape"` fragment class instead of `"core"`.
- Resolved stdlib I/O signatures in the compiler typechecker (`typechecker.rs`) to infer parameterized `Result[T, IoError]` types without relying on dynamic FFI module loading during typecheck.
- Emitted capabilities and effects metadata into `manifest.json` and contract JSON targets for downstream runtime binding.

[S] Shipped / Signals
- Updated `igniter-compiler/src/lexer.rs` adding `capability` and `effect` keywords.
- Updated `igniter-compiler/src/parser.rs` parsing `capability` and `effect` body declarations.
- Updated `igniter-compiler/src/classifier.rs` implementing strict capability mode (read/write), missing/wrong argument checks, and error taxonomy (`E-IO-*`).
- Updated `igniter-compiler/src/typechecker.rs` integrating standard library I/O function signature resolution (`stdlib.IO.*`).
- Updated `igniter-compiler/src/emitter.rs` and `src/assembler.rs` serializing capabilities and effects to compiled output files.
- Six validation fixtures in `fixtures/io_capability/` demonstrating positive and negative verification scenarios.
- `proofs/experimental_io_capability_effect_surface_proof.rb` validating the 12 proof matrices.
- `lab-docs/lab-experimental-io-capability-effect-surface-proof-v0.md` detailing design and verification.

[T] Tests / Proofs
- Executed `ruby proofs/experimental_io_capability_effect_surface_proof.rb` showing 12/12 checks passed (0 failures).
- Ran general compiler test suite `ruby verify_compiler.rb` verifying no regression on mainline/golden test targets.
- Verified mainline code repository `../igniter-lang` is completely clean and untouched.

[R] Risks / Recommendations
- Recommended next slice: Proceed with designing the runtime loader and dynamic resolution machine for capabilities/effects using receipts and observations generated under LAB-STDLIB-IO-P1.
