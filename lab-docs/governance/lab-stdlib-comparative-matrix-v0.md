# Igniter Stdlib Comparative Matrix & Analysis v0

**Status:** DRAFT / ANALYSIS  
**Focus:** Pure functional deterministic domain pressure  
**Date:** 2026-06-11  

## 1. The Comparative Matrix

This matrix evaluates Igniter's standard library (`stdlib`) philosophy against three mainstream paradigms: Systems/Safety (Rust), Pragmatic/Concurrency (Go), and Dynamic/Web (TypeScript).

| Feature / Domain | Igniter (v0 Core) | Rust (`std`) | Go (`stdlib`) | TypeScript / JS |
| :--- | :--- | :--- | :--- | :--- |
| **Collections & Iteration** | `fold`, `map`, `filter`. Must be statically bounded. No unbounded `while` loops. | Extensible `Iterator` trait. Unbounded iteration allowed. | Imperative `for` loops. Ranging over slices/maps. | Dynamic `Array.prototype`. Unbounded iteration allowed. |
| **Null & Missing Values** | Strict `Option[T]`. `none()` / `some(v)`. Unwraps required. | Strict `Option<T>`. Advanced combinators. | Multiple returns `(val, ok)`. Pointers can be `nil`. | Pervasive `null` and `undefined`. Optional chaining. |
| **Error Handling** | Strict `Result[T, E]`. Must be matched or folded. | Strict `Result<T, E>` with `?` operator syntax sugar. | Multiple returns `(val, error)`. Requires manual `if err != nil`. | Exceptions (`throw` / `try...catch`). |
| **Strings & Text** | Strict `Text`. Operations explicitly bound to `Byte`, `Rune`, or `Grapheme`. | `String` (UTF-8 bytes) and `char` (Unicode Scalar Value). | `string` (read-only byte slice) and `rune` (int32). | UTF-16 encoded `String`. Length is UTF-16 code units. |
| **Numeric Precision** | Explicit `Decimal[N]` for financial accuracy. `Integer`, `Float`. | `f32`, `f64`, integer types. `Decimal` requires 3rd-party crates. | `float32`, `float64`, ints. `Decimal` requires 3rd-party packages. | Unified `number` (IEEE 754 Float64). `BigInt` available. |
| **Time & Clocks** | Pure arithmetic only. **`now()` is strictly OOF**. Time is an injected environment dependency. | `std::time::SystemTime::now()` available everywhere. | `time.Now()` available everywhere. | `Date.now()` available everywhere. |
| **I/O & Networking** | **OOF (Out-Of-Frame)**. Entirely banned from the pure computational core. | Comprehensive file system, TCP/UDP sockets, stdio. | Massive standard library for HTTP, OS, net, crypto, IO. | Host-provided APIs (Node `fs`, Browser `fetch`). |
| **Recursion** | Managed (`decreases fuel`). Unbounded self-reference throws `OOF-L4`. | Allowed natively. Call stack overflows possible. | Allowed natively. Call stack overflows possible. | Allowed natively. Call stack overflows possible. |

---

## 2. Philosophical Divergence: Why Igniter is Different

Mainstream languages optimize for **developer velocity and system integration** (e.g., easy access to the network, file system, and system clock). 

Igniter optimizes for **absolute computational determinism and auditable proof limits**.
1. **The Ambient Ban:** Igniter deliberately removes `now()`, `random()`, and `fetch()` from the `stdlib` because pure contracts must yield identical outputs for identical inputs, regardless of when or where they execute.
2. **Termination Guarantees:** Mainstream languages accept the Halting Problem and allow infinite loops. Igniter demands termination proofs (`decreases fuel` for recursion, and finite collection bounds). The `stdlib` is designed to operate safely inside a computational gas/fuel budget.
3. **Domain Correctness over Convenience:** The explicit separation of `Byte`, `Rune`, and `Grapheme` processing, along with native `Decimal[N]` parameterisation, shows Igniter prioritizes correctness for financial and scientific domains over ergonomic shortcuts (like JS's `number` or Go's generic `len(string)`).

---

## 3. "Where Gravity Pulls": Focus Areas for `LAB-STDLIB-FOUNDATION`

Based on recent domain pressure tests across Bookkeeping, Spreadsheet engines, and ERP Logistics, the immediate gravitational pull is toward **removing friction in basic computational algebra**. The language architecture is sound, but the compiler implementations are trailing the specification.

### Immediate Priority (The Friction Boundary)
*   **Operator Implementation:** The Rust typechecker explicitly rejects binary operations on `Float` and `Decimal` (e.g., `Float < Float` or `Decimal == Decimal`). Mathematical operators must be expanded beyond `Integer`.
*   **Literal Instantiation:** A mechanism to instantiate `Decimal` values natively (e.g. `100.00D`) is urgently needed, as standard floats fail type unification against decimal bounds.
*   **Unary Operators:** The parser must be updated to correctly tokenize prefix operators on numeric literals (e.g., `-1.0`).

### Near-Term Priority (The Composition Boundary)
*   **Build Pipeline Orchestration:** Our tests proved that the `igniter-compiler` *can* bridge the `TypeEnv` across multiple files if invoked correctly (`cargo run compile a.ig b.ig`). The ruby `igc` wrapper must be updated to resolve `import` statements and feed the full dependency graph to the compiler backend.
*   **Variant Ergonomics:** `stdlib.result.ok` requires full namespace qualification. The language needs to decide if core variant constructors (`some`, `none`, `ok`, `err`) should be implicitly available in the global prelude.

### Long-Term Priority (The Complexity Boundary)
*   **Regex / Advanced Text:** Currently deferred. When implemented, it must respect computational fuel limits to prevent ReDoS (Regular Expression Denial of Service), which aligns with the "Managed Recursion" philosophy.
*   **Parser Combinators:** Without a native `eval` or loops, writing domain-specific language parsers (like spreadsheet formulas) requires combinators that play nicely with `decreases fuel`.
