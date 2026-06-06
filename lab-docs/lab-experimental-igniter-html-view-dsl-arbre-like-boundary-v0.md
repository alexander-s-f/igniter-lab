# Lab Experimental Igniter HTML View DSL (Arbre-like Boundary v0)

Status: `experimental · lab-only`
Track: `lab-experimental-igniter-html-view-dsl-arbre-like-boundary-v0`
Base: `PROP-Forms-Enhanced-v0.md`, `Language Covenant (Postulate 27 & 28)`

---

## 1. Context & Motivation

Igniter contracts define business logic as validated dependency graphs. In an application environment (such as an interactive IDE mockup or a real administrative dashboard), displaying this logic requires presenting data to human operators.

This document explores how an **Arbre-like HTML view engine** can be modeled using Igniter-style concepts (inputs, computes, outputs, and contract invocation forms). Crucially, this research is a **lab-only frontier pressure test** to examine code structures and check how they map to the compile-time and runtime assumptions of Igniter-Lang.

---

## 2. Syntax Candidates

We analyze three syntax candidates for expressing HTML view trees in Igniter.

### Candidate A: Pure Block/Tree DSL

In this candidate, we introduce a specialized `render` node or block inside a contract. Inside this block, standard HTML tags act as builder primitives.

```igniter
contract TodoPage {
  input title: String
  input items: Collection[TodoItem]

  compute total_count = items.count()

  output page: HtmlDocument

  render {
    html {
      head {
        title(title)
        link(rel: "stylesheet", href: "/assets/ig-brand.css")
      }
      body(class: "ig-field") {
        h1(title, class: "text-ignite font-bold")
        p("Total items: " ++ total_count.to_string())
        div(class: "list-container reg") {
          div(class: "tr")
          div(class: "bl")
          items.each { item ->
            div(class: "card border-line p-4 m-2") {
              span(item.title, class: "text-grey-3")
              span(item.status, class: "text-amber font-mono")
            }
          }
        }
      }
    }
  }
}
```

*   **Pros:** Clean, highly readable, matches established conventions (Arbre, builder, Svelte/React JSX structure).
*   **Cons:** Introduces a complex imperative-looking builder block inside a language that enforces immutable dependency graphs (`Postulate 1`).

---

### Candidate B: Contract-Output DSL (Contracts as Components)

In this candidate, a "component" is simply a standard Igniter contract whose output is an `HtmlNode` or `HtmlDocument`. Standard contract composition is used to nest components.

```igniter
contract TodoCard {
  input item: TodoItem
  output node: HtmlNode

  compute status_class = if item.completed { "text-ok" } else { "text-no" }

  output node = div(class: "card") {
    span(item.title, class: "text-grey-3")
    span(item.status, class: status_class)
  }
}

contract TodoPage {
  input title: String
  input items: Collection[TodoItem]
  output document: HtmlDocument

  output document = html {
    body(class: "ig-field") {
      h1(title)
      div(class: "list-container") {
        items.map { item -> TodoCard(item: item) }
      }
    }
  }
}
```

*   **Pros:** Fits perfectly into Igniter's core identity (`Postulate 20 — Contracts Compose`). The component contract can declare type safety, dependencies, and caching characteristics just like any other contract.
*   **Cons:** Syntax can feel verbose when doing rapid UI iteration. Passing arguments explicitly (`item: item`) adds friction.

---

### Candidate C: Forms-Assisted Component/Tag Invocation DSL

This candidate explores using **Contract Invocation Forms** to invoke HTML view components. Under `PROP-Forms-Enhanced-v0`, a contract can declare a `form` mapping. We can leverage this to declare syntax sugar for UI components:

```igniter
contract TodoCard(item: TodoItem) -> result: HtmlNode
  form "todo_card" (item)
  priority 10
{
  result = div(class: "card") {
    span(item.title)
  }
}
```

Then, in the page render, we invoke the component using its registered form:

```igniter
contract TodoPage {
  input items: Collection[TodoItem]
  output doc: HtmlDocument

  output doc = html {
    body {
      items.map { item ->
        -- Invocation via form alias:
        todo_card item
      }
    }
  }
}
```

*   **Pros:** Combines the strict type-safety of Candidate B with the brief ergonomic layout of Candidate A.
*   **Cons:** Increases scope and complexity of the compiler's form-resolution registry.

---

## 3. Analysis & Design Decisions

### 3.1 Evaluating the `form:` Prefix for DX Sugar

We evaluated whether a `form:` prefix or modifier improves DX for component/tag invocation, or if it creates ambiguity.

*   **Ambiguity:** Using the syntax `form:todo_card(item)` makes it explicitly clear that we are invoking a contract form, preventing name collisions with normal functions or variables.
*   **Composition:** However, Igniter's core axiom is **Honesty**. Syntactic sugar should not hide reality. If a form is resolved statically to a `ContractInvocation` during compilation, the source code should be easily readable by both human and agent.
*   **Conclusion:** The `form:` prefix should remain a **DX candidate only** for tag/component invocation. It acts as an **invocation alias** that resolves to a `ContractInvocation` node. It should not be a runtime primitive.

### 3.2 HTML Tags: Primitives vs Component Contracts

Should HTML tags (`div`, `span`, etc.) be primitive compiler builder calls or standard component contracts?

*   **Decision:** HTML tags should be represented as **primitive view node builders** (`HtmlNode` constructors), not individual contracts. If every `div` were a contract, a single web page would compile into thousands of contract nodes, overwhelming the dependency resolution engine and compile-time validation rules.
*   **Lowering:** Components, however, are contracts. They should lower to an `HtmlNode` tree. At compile-time, the component is type-checked, and at runtime, it evaluates to produce its corresponding branch of the `HtmlNode` tree.

---

## 4. Answers to Core Questions

1.  **Is this better modeled as a language feature, IDE/frontier framework feature, or external view-engine package?**
    *   *Answer:* The core HTML view tree representation (`HtmlNode` and safe escaping) belongs to an **external view-engine package** or library. However, the ability to compile components, trace dependencies through view nodes, and output visual diagnostic images is an **IDE/frontier framework feature**.
2.  **Does `form:` improve composition and DX for view components?**
    *   *Answer:* Yes. It allows custom component names to be invoked cleanly without verbose namespace qualification or constructor syntax, aligning with how custom operators are registered.
3.  **Is `form:` acting as a constructor, invocation alias, component adapter, or something else?**
    *   *Answer:* It acts as an **invocation alias** that desugars to an explicit `ContractInvocation`.
4.  **Should HTML tags be primitive builder calls or component contracts?**
    *   *Answer:* HTML tags are primitive builder calls (`HtmlNode` constructors). Custom reusable UI widgets are component contracts.
5.  **Should components lower to `HtmlNode` trees, SemanticIR-like artifacts, or a separate view IR?**
    *   *Answer:* Components should lower directly to an `HtmlNode` tree. The view-tree structure is itself serialized as a standard JSON artifact (`view_tree.json`), which is compatible with SemanticIR's node types.
6.  **Does this require forms lowering, or can it stand alone as a lab engine?**
    *   *Answer:* It stands alone as a lab engine. The prototype parses Ruby DSL blocks, builds a structured node representation, and generates standard HTML and JSON evidence without modifying the Rust compiler core.
7.  **What is the smallest next proof after P1?**
    *   *Answer:* P2: Integrating the generated `view_tree.json` directly into the Svelte-based Igniter IDE panel (`igniter-ide`) to display live-updating contract component previews.

---

## 5. Prototype Architecture & Verification

The prototype `igniter-view-engine` implements a Ruby-based view representation under `igniter-lab/igniter-view-engine/`:

*   `HtmlNode`: Immutable representation of tag, attributes, children, and escaping state.
*   `ParserBuilder`: Block-based DSL evaluator that handles nesting, attributes, conditions, and loops.
*   `run_proof.rb`: Builds fixtures, evaluates them, runs proof validations (VDSL-1 to VDSL-12), and outputs artifacts to `out/`.

### Proof Matrix Verification Results

| Rule ID | Requirement | Result | Verification Notes |
|---------|-------------|--------|---------------------|
| **VDSL-1** | Static view builds a valid view tree | `PASS` | Evaluates static page blocks to correct `HtmlNode` tree structure. |
| **VDSL-2** | Data-driven list renders deterministic HTML | `PASS` | Renders dynamic collection values to deterministic HTML strings. |
| **VDSL-3** | Component invocation is represented as structured nodes, not string concatenation | `PASS` | Components exist as first-class `component` nodes with `is_component: true` in the AST. |
| **VDSL-4** | Attributes/classes/styles are inspectable in JSON | `PASS` | Attributes and CSS classes are fully serializable and visible in `view_tree.json`. |
| **VDSL-5** | Text content is escaped by default | `PASS` | Evaluated special characters like `<` and `>` are encoded as `&lt;` and `&gt;`. |
| **VDSL-6** | Unsafe/raw HTML requires explicit marker | `PASS` | Unescaped code is printed literally only when wrapped in `IgniterView.raw`. |
| **VDSL-7** | Conditional rendering is visible in trace/artifact | `PASS` | Components dynamically check condition flags, which are captured in diagnostics. |
| **VDSL-8** | Collection rendering is visible in trace/artifact | `PASS` | Children trace contexts retain active loop index metadata (`loop_index_0`, etc.). |
| **VDSL-9** | Forms-assisted syntax, if explored, is marked DX candidate only | `PASS` | Invocation via the `form` helper sets `forms_assisted: true` in node metadata. |
| **VDSL-10**| Output HTML and view_tree.json are reproducible | `PASS` | Generates identical, reproducible output files under the `out/` directory. |
| **VDSL-11**| No mainline files are edited | `PASS` | No files in `igniter-lang/` or mainline compiler directories were modified. |
| **VDSL-12**| No canon/stable/public/runtime claims are introduced | `PASS` | Retained purely as a lab-local playground experiment. |
