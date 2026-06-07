# Compiler First Proof

Status: active seed

Goal: compile one small `.ig` fixture, inspect the generated `.igapp` bundle,
and understand what kind of evidence the compiler produces.

This lesson uses the experimental compiler in `igniter-compiler/`. It is a
pre-v1 lab walkthrough: commands and artifact shapes are useful today and may
change as the compiler evolves.

## Read

Start with these files:

| File | Why It Matters |
| --- | --- |
| [Compiler README](../../igniter-compiler/README.md) | Pipeline, package boundary, and local commands. |
| [Add fixture](../../igniter-compiler/fixtures/conformance/source/add.ig) | Tiny source contract used as the first compiler input. |
| [Compiler verifier](../../igniter-compiler/verify_compiler.rb) | Batch proof runner for conformance fixtures. |

The fixture is intentionally small:

```igniter
module Lang.Examples.Add

contract Add {
  input  a: Integer
  input  b: Integer

  compute sum = a + b

  output sum: Integer
}
```

## Try

From the repository root:

```bash
cd igniter-compiler
cargo run -- compile fixtures/conformance/source/add.ig --out out/tutorial_add.igapp
```

For a broader compiler smoke check:

```bash
ruby igniter-compiler/verify_compiler.rb
```

If the release binary is missing, `verify_compiler.rb` rebuilds it before
running the fixture matrix.

## Observe

After the compile command, inspect the output directory:

```bash
find out/tutorial_add.igapp -maxdepth 2 -type f | sort
```

Expected status in the compiler JSON:

```json
{
  "status": "ok",
  "contracts": ["Add"],
  "stages": {
    "parse": "ok",
    "classify": "ok",
    "typecheck": "ok",
    "emit": "ok",
    "assemble": "ok"
  }
}
```

Useful artifacts include:

| Artifact | What To Inspect |
| --- | --- |
| `manifest.json` | Bundle identity, contract list, and high-level classification. |
| `semantic_ir_program.json` | Lowered program representation used by later proof surfaces. |
| `compilation_report.json` | Compiler status and diagnostic-oriented summary when emitted. |
| `contracts/add.json` | Contract-level assembled artifact for the `Add` fixture. |
| `classified_ast.json` | Classifier output before SemanticIR emission. |
| `form_table.json` / `form_resolution_trace.json` | Forms sidecars emitted by the current lab compiler. |
| diagnostics sidecars | Boundary failures, warnings, or proof-local checks when present. |

The exact artifact set may change between lab slices. Treat this lesson as a
way to learn the evidence shape, not as a frozen output contract.

## What This Shows

This walkthrough can show that the current lab compiler can parse and emit a
bundle for the `Add` fixture in your local checkout.

Current development notes:

- grammar and compiler APIs may change before v1;
- `.igapp` output is an inspectable lab artifact, not a promise of execution support;
- VM/runtime behavior is verified in separate proof surfaces;
- performance and portability are not the focus of this first lesson.

## Boundary

The compiler is an active lab package provided as-is for learning and feedback.
Formal language authority lives in `igniter-lang`; this lesson helps you inspect
the current lab evidence shape.

## Troubleshooting

| Symptom | Next Step |
| --- | --- |
| `cargo` is missing | Install Rust/Cargo before running compiler commands. |
| compile command fails | Run `cargo test` inside `igniter-compiler/` and inspect the first compiler diagnostic. |
| output directory is missing | Confirm the command was run from `igniter-compiler/` and the `--out` path is writable. |
| generated files appear in `git status` | Keep `out/` generated output untracked unless a specific proof card asks for it. |
