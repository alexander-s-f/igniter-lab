# DecisionTree Library for Igniter

An arena-based Decision Tree library written in Igniter, with a loan approval example.

## Architecture

```text
types.ig        -> Core data structures (TreeNode, DataRow, Prediction)
builder.ig      -> Tree construction (MakeLeaf, MakeDecision, AddNode)
evaluator.ig    -> Tree traversal and classification (FindNodeById, EvalDecision, Evaluate)
example.ig      -> Loan approval example (BuildLoanTree, RunLoanExample)
```

## Arena-Based Tree Model

Since Igniter does not currently expose recursive data types or a stable ADT surface, the tree is modeled as a flat arena. All nodes live in `DecisionTree.nodes`, and children are referenced through String IDs (`left_id`, `right_id`).

```igniter
type TreeNode {
  id : String
  kind : String
  feature_name : String?
  threshold : Integer?
  left_id : String?
  right_id : String?
  label : String?
  confidence : Integer?
}
```

## Pressure Docs

- [`report.md`](report.md) - live compiler findings and pressure analysis.
- [`PRESSURE_REGISTRY.md`](PRESSURE_REGISTRY.md) - concise pressure IDs and suggested routes.

## Current Compile Status

Rust real multi-file compile currently stops on stdlib import resolution:

```text
OOF-IMP2 unknown import path 'stdlib.collection'
```

Ruby real multi-file compile currently stops earlier on parser keyword hygiene:

```text
ParseError: Expected name, got keyword(label)
```

Probe runs show downstream pressure around `append`, text equality, stringly `call_contract`, and single-element extraction from collections.

## Testing

Rust lab compiler:

```bash
cargo run -- compile ../igniter-apps/decision_tree/types.ig ../igniter-apps/decision_tree/builder.ig ../igniter-apps/decision_tree/evaluator.ig ../igniter-apps/decision_tree/example.ig --out /tmp/decision-tree-rust.igapp
```

Ruby canon compiler:

```bash
ruby -Ilib -e 'require "igniter_lang/compiler_orchestrator"; paths = %w[types.ig builder.ig evaluator.ig example.ig].map { |f| File.expand_path("../igniter-lab/igniter-apps/decision_tree/#{f}", __dir__) }; result = IgniterLang::CompilerOrchestrator.new.compile_sources(source_paths: paths, out_path: "/tmp/decision-tree-ruby.igapp"); puts JSON.pretty_generate(result)'
```
