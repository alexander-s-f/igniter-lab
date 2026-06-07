# Site Projection Excerpts

These excerpts are curated summaries and site-ready source copy that can be
adapted by user-facing websites such as `igniter-org` without copying the full
laboratory development history.

---

## Pre-v1 Feedback Note

> ### Welcome to the Igniter Frontier
>
> We are actively shaping the future of Igniter. The toolchains, compilers, and virtual machine designs featured here represent active, pre-v1 exploration. 
> 
> Because this is a workspace for active feedback and iteration:
> - Syntax formats, intermediate files, and APIs are subject to change.
> - These resources are provided **as-is** for community learning, experimentation, and design discussion.
> - Official specification guidelines and stable compiler releases remain governed by formal mainline review paths.
> 
> We invite you to build, test, and discuss these designs with us!

---

## Lesson Excerpts

### Lesson 0: Lab Orientation
- **Summary**: Get familiar with the layout of the lab repository, key component packages (compiler, VM, stdlib, IDE), and the evidence vocabulary.
- **What You Will Learn**: How to navigate the experimental packages and confirm your local workspace setup.
- **Try This Command**:
  ```bash
  cd igniter-vm && cargo test
  ```

### Lesson 1: Compiler First Proof
- **Summary**: Compile a simple addition contract using the experimental compiler to inspect AST structures and generated bundle formats.
- **What You Will Learn**: How the compiler parses, classifies, and monomorphizes `.ig` files into `.igapp` intermediate directories.
- **Try This Command**:
  ```bash
  cargo run --manifest-path igniter-compiler/Cargo.toml -- compile igniter-compiler/fixtures/conformance/source/add.ig --out igniter-compiler/out/tutorial_add.igapp
  ```

### Lesson 2: VM Candidate Proof
- **Summary**: Execute a linear instruction proof matrix inside the candidate Tokio-based VM and read the generated result packet.
- **What You Will Learn**: How bytecode instructions execute registers, handle stack variables, and output audit observations.
- **Try This Command**:
  ```bash
  ruby igniter-vm/proofs/vm_candidate_proof.rb
  ```

### Lesson 3: Forms First Proof
- **Summary**: Trace custom operators (like `+` and `++`) from parsed source fixtures to static compiler-resolved form lookup tables.
- **What You Will Learn**: How type-directed dispatch maps operator syntax triggers to specific contract implementations at compile-time.
- **Try This Command**:
  ```bash
  cargo run --manifest-path igniter-compiler/Cargo.toml -- compile igniter-compiler/fixtures/forms/positive_forms.ig --out igniter-compiler/out/forms_test.igapp
  ```

### Lesson 4: Capability Passport First Proof
- **Summary**: Load compiled application fixtures through the VM capability passport and test fail-closed security bounds.
- **What You Will Learn**: How the loader guards against file path escapes, ambient authorization leaks, and code tampering.
- **Try This Command**:
  ```bash
  ruby igniter-vm/proofs/io_vm_loader_capability_passport_integration.rb
  ```

### Lesson 5: View / GUI / IDE First Proof
- **Summary**: Compile a View DSL layout template, solve UI bounding boxes headlessly, and inspect the trace inside the Svelte IDE check.
- **What You Will Learn**: How layout solves and view trees compile to static JSON files for safe visual previews without running contract code.
- **Try This Command**:
  ```bash
  ruby igniter-view-engine/run_proof.rb
  ```
