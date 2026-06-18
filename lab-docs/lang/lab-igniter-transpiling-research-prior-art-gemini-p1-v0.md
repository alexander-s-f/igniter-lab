# lab-igniter-transpiling-research-prior-art-gemini-p1-v0 — Prior Art & Anti-Patterns for Projection Dialects

**Delegation-Code:** `GEMINI-20260618-TRANSPILING-D`  
**Status:** RESEARCH REPORT (v0; prior-art interpretation, not authority)  
**Target Card:** `LAB-IGNITER-TRANSPILING-RESEARCH-PRIOR-ART-GEMINI-P1`  
**Authority:** Lab research only. No code edits. No canon authority.

---

## 1. Executive Summary

This report evaluates prior art in transpilation, template languages, and code generation across mature ecosystems (TypeScript/Babel, Svelte/Astro, GraphQL, Rails, and Rust) to guide the evolution of **Igniter Projection Dialects** (`.igv`, `.igweb`). The core objective of this research is to identify patterns worth borrowing and anti-patterns that Igniter must reject to prevent dialects from smuggling hidden runtime authority, causing semantic drift, or creating untraceable debugging gaps.

---

## 2. Prior Art Lenses & Analysis

We evaluate the following seven prior-art domains to extract architectural constraints for Igniter:

### A. TypeScript / Babel / SWC (Source-to-Source Lowering)
*   **Observations:** TypeScript and Babel perform syntactic transpilation and type erasure, producing standard ECMAScript. They do not introduce new execution runtimes; they lower to existing targets.
*   **Borrowable Pattern:** Pure syntactic compilation. The source dialect simplifies developer expression, but the target code is the standard source of truth.
*   **Anti-pattern to Avoid:** "Magic" polyfills injected implicitly by the transpiler. If a compiler automatically injects runtime libraries or hidden global state variables, debugging becomes opaque.

### B. Svelte / Astro / Vue (Single-File Component Compilation)
*   **Observations:** Svelte parses HTML, CSS, and JS in a single file and compiles it into highly efficient, vanilla DOM-manipulation instructions.
*   **Borrowable Pattern:** Declarative compilation to JSON/AST structures. The compiler acts as a static layout optimizer, transforming ergonomics into rigid, static structural data (matching `.igv` lowering to `ViewArtifact JSON`).
*   **Anti-pattern to Avoid:** Hidden reactivity/runtime tracking. Vue/Svelte inject dynamic reactivity wrappers or proxies. Igniter's UI layer must remain completely machine-free and stateless at compile time.

### C. GraphQL Codegen & Schema-First Workflows
*   **Observations:** GraphQL compiles schema files (`.graphql`) into typed code artifacts (e.g., TS interfaces, Rust structs). The schema is the strict contract.
*   **Borrowable Pattern:** Generation of inspectable, check-in ready code artifacts. The generated files are checked into version control, meaning they can be reviewed and audited.
*   **Anti-pattern to Avoid:** Stale generated code. If code-generation is not enforced by CI, the schema and the generated code drift.

### D. Rails / Rack Routing DSLs
*   **Observations:** Rails uses dynamic, evaluation-time DSLs (like `config/routes.rb`) that build runtime lookup tables using reflection and dynamic metaprogramming (`method_missing`).
*   **Borrowable Pattern:** High-level declarative layout for paths and methods.
*   **Anti-pattern to Avoid:** Dynamic route tables. Because Igniter has no dynamic contract dispatch (enforces compile-time literal contract names), dynamic lookup is uncompilable. Igniter must statically lower routes into explicit compile-time matches (`call_contract`).

### E. SQL Query Builders & ORM Migrations
*   **Observations:** Tools like Diesel or Active Record generate static schema snapshots from migration files.
*   **Borrowable Pattern:** The migration/schema file acts as the audited blueprint.
*   **Anti-pattern to Avoid:** Hidden migration side-effects.

### F. Macro Hygiene in Rust / Lisp / Scala
*   **Observations:** Rust enforces hygiene, preventing macro expansion from accidentally capturing or leaking variables in the calling scope.
*   **Borrowable Pattern:** Strict scoping. Lowering passes must not capture or depend on out-of-scope variables unless explicitly declared.
*   **Anti-pattern to Avoid:** Unhygienic identifier resolution.

### G. JSX / MDX / Templating Surfaces
*   **Observations:** JSX and MDX allow embedding arbitrary Turing-complete expressions within declarative markup.
*   **Borrowable Pattern:** None.
*   **Anti-pattern to Avoid:** Smuggling runtime authority. Embedding arbitrary IO, effect execution, or DB queries inside markup. Igniter must enforce that view files (`.igv`) only name *logical targets*, leaving execution to the host.

---

## 3. Targeted Answers to Research Questions

### Q1: What patterns map well to Igniter's Projection Dialects?
*   **Static AST Lowering (Svelte/Astro):** Transforming declarative syntactic shortcuts into rigid, inspectable targets (`.igv` -> JSON; `.igweb` -> `.ig`).
*   **Contract Code-Generation (GraphQL):** Generating static, type-safe target code that can be statically checked and compiled by the primary compiler without runtime overhead.
*   **Schema-as-Contract:** Using schema/routing files to define interface boundaries while leaving implementation details to standard code.

### Q2: What patterns are dangerous because they hide runtime authority?
*   **JSX-style Arbitrary Code Execution:** Permitting arbitrary logic, state mutations, or IO inside view files.
*   **Dynamic Metaprogramming (Rails):** Attempting to resolve endpoints dynamically at runtime. This violates Igniter's static compile-time registry guarantees and defeats static analysis.
*   **Implicit Build-time Injections:** Injecting uninspectable helper libraries, runtime schedulers, or security tokens during the compilation pass.

### Q3: How do mature ecosystems handle generated artifact inspection?
Mature systems prevent debugging gaps by enforcing **inspectable, version-controlled artifacts**:
*   Rather than hiding generated files in untracked build directories (e.g., `.next/` or `target/`), the output of the lowering pass (such as the generated `.ig` routing contract) must be written directly to the codebase and checked into version control.
*   This makes the generated code fully reviewable during PRs and allows standard tools (compilers, linters) to operate on the output without needing specialized knowledge of the dialect.

### Q4: How do they handle source maps and IDE errors?
*   **Source Maps:** They output mapping files linking the generated lines back to the source lines.
*   **IDE Diagnostics:** LSPs run lightweight parsers directly on the dialect files to report diagnostics at the correct character offsets.
*   **Igniter Recommendation:** The lowerer must emit line-positioned errors (`IgvError { line, msg }`). For downstream compiler errors on the generated code, a simple line-mapping layout must be documented, enabling IDE tools to map warnings/errors back to the original dialect file.

### Q5: How do they prevent dialect proliferation?
*   Ecosystems like Babel suffered from "plugin fatigue" where every project had custom transforms, rendering codebases incompatible.
*   **Igniter Recommendation:** Maintain a centralized, documented **Dialect Registry** with strict smell tests. Custom/app-local dialects are permitted only if they use explicit namespace prefixes (e.g., `acme.igworkflow`) and satisfy the core invariants (no hidden authority, deterministic, inspectable).

### Q6: What governance terms or promotion ladders are worth borrowing?
*   We recommend formalizing the **ECMA TC39 Stage Proposal** concept adapted for Igniter:
    `private` (local project) -> `lab` (functional, tested in-tree) -> `experimental` (shared for trial across select projects) -> `canon-candidate` (proposed for language integration) -> `canon` (integrated into the compiler).
*   A clear boundary must be enforced: no amount of popularity in the `lab` stage creates `canon` authority without a formal design decision.

### Q7: What should Igniter explicitly reject even if other ecosystems accept it?
*   **Turing-complete views/routing:** MDX-style embedded logic in `.igv` files or custom filters in `.igweb`.
*   **Runtime Reflection / Eval:** Generating or running code dynamically without compilation checks.
*   **Invisible Code Generation:** Writing generated code only to temp folders.

### Q8: What surprising idea should the main wave consider that is not already in P0?
*   **CI-enforced Dialect Verification (`igniter dialect verify`):**
    To prevent developers from accidentally modifying the generated `.ig` or JSON output files by hand (which breaks the single source of truth contract), the CLI should provide a verification command. In CI, this command runs the lowerer on the source dialect and asserts that the output is byte-identical to the committed file. If it is not, the build fails. This ensures that the dialect remains the absolute source of truth.

---

## 4. Rejection & Anti-Proliferation Rules
A new `.ig*` dialect is justified **only** if:
1.  It lowers to an already existing, inspectable canonical target.
2.  It introduces no new runtime, dynamic dispatch, or hidden authority.
3.  It significantly reduces boilerplate compared to the target.
4.  It could not be solved by writing a standard `.ig` contract or library helper.

---

## 5. Next Recommended Cards
1.  **`LAB-IGNITER-DIALECT-VERIFY-P2` (Tooling):** Implement the `igniter dialect verify` command in the CLI to validate that committed generated files match their source dialects.
2.  **`LAB-IGNITER-SOURCE-MAP-RESOLVER-P3` (IDE/DX):** Implement a simple line-mapping resolver to route compiler diagnostics from generated `.ig` files back to their `.igweb` origins.
