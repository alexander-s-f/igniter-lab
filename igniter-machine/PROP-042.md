# PROP-042: Fused Machine Prototype Sketch

Status: `frontier-proposal-sketch`
Surface: `igniter-lab/igniter-machine`
Authority: no canon, no runtime support, no stable `.igm` format

## Summary

`igniter-machine` explores a fused local controller for the lab compiler, VM,
and TBackend playground. The working question is whether a single process can
load compiled contracts, dispatch them through the VM, read/write temporal
facts, collect observations, and checkpoint the local state into a candidate
image artifact.

This document is research input only. It does not establish the Igniter Lang
runtime, a Reference Runtime, a public API, package surface, release surface,
or a stable image format.

## Prototype Components

| Component | Prototype role | Authority status |
| --- | --- | --- |
| `IgniterMachine` | Local controller for registry, backend, observations, and dispatch. | Lab-only. |
| `ContractRegistry` | Holds compiled contract JSON for dispatch experiments. | Lab-only. |
| `TBackend` trait | Adapter boundary for in-memory, filesystem-backed, and remote TCP experiments. | Lab-only. |
| `MachineVMBackendAdapter` | Connects VM load/write needs to the prototype backend. | Lab-only. |
| `.igm` checkpoint | Candidate serialized state artifact containing contracts, facts, and observations. | Unstable local artifact only. |
| Ruby FFI | Magnus bridge for local verification. | Lab-only. |
| REPL / MCP-style stdio | Developer-facing experiment surfaces. | Lab-only. |

## Candidate `.igm` Image Idea

The prototype currently treats `.igm` as a local checkpoint artifact. A future
spec route would need to define, at minimum:

- magic/version metadata;
- registry payload shape;
- fact and observation serialization shape;
- compatibility and migration rules;
- integrity/digest requirements;
- failure behavior for malformed or incompatible images;
- explicit non-goals around release, portability, and public compatibility.

Until that route exists, `.igm` files are local lab outputs only.

## Open Design Questions

1. Should a fused controller exist at all, or should compiler, VM, and temporal
   storage remain separately composed by external tooling?
2. If a fused controller remains useful, which API is the smallest stable
   candidate: load/check/dispatch, fact write/read, checkpoint/resume, or none
   before v1?
3. Should Ruby FFI remain a lab bridge, or become a separate package after the
   language/runtime split?
4. Should REPL and MCP-style surfaces be developer tools only, or part of a
   later IDE/debugger line?
5. What proof matrix is required before any Main Line design intake?

## Suggested Future Route

If this idea returns to Main Line, route it as a bounded intake/design card:

- read lab prototype and test evidence;
- separate fused-machine concept from runtime authority;
- decide whether `.igm` belongs in spec/proposal work;
- keep implementation, package, release, and public claims closed unless a
  later authorization review explicitly opens them.
