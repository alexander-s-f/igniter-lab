# Ruby IVM Runtime Research

`igniter-research/ivm-ruby-runtime` preserves early Ruby IVM and native-runner
research that informed later Igniter VM work.

This package is a research/archive surface. It is not the active Igniter VM,
not public runtime support, not Reference Runtime support, not a stable API,
and not a production or release surface.

## Current Role

This package preserves proof-local research around:

- Ruby IVM instruction execution and bytecode sketches;
- compiler artifact to IVM adapter experiments;
- lazy branch and comparison behavior proofs;
- native C runner and `.igbin` file-loading experiments;
- resident supervisor intake sketches;
- capability delegation and passport hardening prototypes.

The active Rust VM candidate lives in `../../igniter-vm/`. This package should
be read as historical/frontier evidence, not as a product runtime.

## Layout

- `lib/ivm.rb` defines the local Ruby IVM namespace and loader.
- `lib/ivm/` contains Ruby VM, instruction, compiler, backend, and C runner sketches.
- `examples/` contains proof scripts and historical research runners.
- `fixtures/` contains small `.ig` and passport fixtures used by proof scripts.
- `docs/` contains research reports and prototype notes.
- `out/` is generated proof output and is intentionally ignored by git.

## Useful Entry Points

```bash
ruby -Ilib examples/demo.rb
ruby -Ilib examples/io_capability_delegation_proof.rb
ruby -Ilib examples/io_capability_delegation_manifest_hardening.rb
```

Some older adapter/AOT/supervisor scripts depend on historical proof artifacts
or mainline paths that may not exist in this split repository. Treat those as
preserved research inputs unless a later hardening pass refreshes them.

## Boundary

This package does not create authority for:

- Igniter Lang runtime support;
- public `igc run` behavior;
- `.igapp` or `.igbin` public execution;
- RuntimeSmoke productization;
- Reference Runtime status;
- public API, public CLI, package, release, production, Spark, performance,
  certification, or portability claims.
