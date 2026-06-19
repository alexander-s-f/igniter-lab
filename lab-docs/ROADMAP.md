# igniter-lab: Roadmap

Last updated: 2026-06-19

This roadmap is intentionally compact. It names the next useful frontier
directions without turning lab behavior into canonical language, runtime,
package, release, or production authority.

## Near-Term

| Direction | Next useful work | Boundary |
| --- | --- | --- |
| Cargo workspace root | Add an explicit root workspace only after the domain umbrella move has settled. | Structural convenience only; no crate moves hidden inside it. |
| IgWeb runner polish | Continue manifest/runner DX after `igweb-serve`; defer source-map/diagnostics until requirements harden. | Lab CLI/runner evidence, not stable public CLI. |
| Package/workspace model | Continue workspace/import ownership research before registry/lockfile work. | Research and lab proofs only. |
| Server app boundary | Keep domain apps outside `igniter-server`; grow extension/middleware/app examples from `server/`. | No hardcoded product domains in server core. |
| Language/stdlib | Continue regexp, routing lowering, Option ergonomics, and known loop gaps as bounded cards. | No canon promotion without mainline route. |
| Runtime/machine | Continue explicit capability/security/storage slices as lab proofs. | No live external runtime without human gate. |
| Frame/UI/IDE | Continue frame/UI/console/IDE work under `frame-ui/` and `ide/`. | UI evidence only unless bridged by explicit host proof. |

## Later

| Direction | Trigger |
| --- | --- |
| Source-map / diagnostics for projection dialects | Open when IgWeb/.igv users hit concrete diagnostic pain. |
| Package-level README refresh | Open when a package becomes active again or needs external handoff. |
| Archive/quarantine pass | Open if stale docs or parked stubs obscure active lab signal. |
| Mainline intake | Open only through explicit Igniter Main Line decision routes. |

## Closed Boundaries

The roadmap does not authorize stable API, Reference Runtime status, public
runtime support, production readiness, release evidence, public performance
claims, certification, portability guarantees, or lab behavior as canon.
