# Igniter Lab Learning Path Glossary

This glossary defines the common terms and extensions used throughout the `igniter-lab` learning path.

---

### File Extensions & Artifacts

#### `.ig`
Igniter language source code files. These files contain contract declarations, input/output schemas, and compute logic.

#### `.igapp`
A compiled Igniter application bundle. In this lab, it is represented as a directory containing structured JSON files (including the contract bytecode, SemanticIR program, and capability passports) rather than a single zipped binary.

#### SemanticIR
Semantic Intermediate Representation. The lowered, structured representation of parsed contract declarations. It forms the intermediate AST consumed by VMs, solvers, and compiler diagnostic systems.

---

### Execution & Telemetry

#### Proof Runner
A local verification script (typically written in Ruby or Rust) that builds components, executes test cases, verifies security boundaries, and outputs machine-readable results.

#### Result Packet
A structured JSON telemetry file (typically named `summary.json`) exported by a proof runner. It contains status fields, matrix check results, disclaimers, and proof-local evidence records.

#### Capability Passport
A security manifest file (`passport.json`) packaged inside `.igapp` bundles. It details load-time capability requirements, active path grants, and caller bindings required for safe contract execution.

---

### Language & Compiler Internals

#### Form Table
A compiled lookup table (`form_table.json`) mapping parsed syntax triggers (like custom operators or keywords) to concrete, type-checked contract definitions.

#### Form Resolution Trace
A diagnostic compiler file (`form_resolution_trace.json`) that traces exactly how custom operators were matched and filtered during typecheck-time form resolution.

---

### Frontend & layout

#### View Tree
A static JSON description of UI layout structure (HTML tags, CSS classes, parameters, and slots) compiled from the experimental View DSL.

#### Scene Receipt
A JSON layout solved result detailing bounding coordinates, hit-testing targets, and event intent maps generated headlessly by the GUI layout engine.

---

### Project Lifecycle

#### Pre-v1
An active, early-phase development status. APIs, grammar, and packaging formats are evolving rapidly and subject to iteration.

#### As-Is
The experimental distribution terms. Software, prototypes, and document contents are provided for educational and feedback purposes without warranty of stability, performance, or support.
