# Igniter Apps Lab Prototypes

`igniter-apps` contains small application-shaped lab prototypes used to exercise
Igniter-adjacent runtime, storage, and CLI ideas. These apps are transferred as
frontier evidence and developer test material, not as public examples or product
surface.

## Current Prototypes

| Path | Purpose |
| --- | --- |
| [`benchmark-app/`](benchmark-app/) | Local TBackend stress/latency harness for manual lab checks. |
| [`todolist/`](todolist/) | Temporal todo CLI with WAL-backed history, audit timeline, and point-in-time reads. |

## Todolist Entry Points

| File | Purpose |
| --- | --- |
| [`todolist/todo.rb`](todolist/todo.rb) | CLI entrypoint and command parser. |
| [`todolist/lib/temporal_store.rb`](todolist/lib/temporal_store.rb) | Local temporal store wrapper over the lab TBackend extension. |
| [`todolist/lib/repl.rb`](todolist/lib/repl.rb) | Interactive REPL. |
| [`todolist/lib/ui.rb`](todolist/lib/ui.rb) | CLI rendering helpers. |

`todolist/todo.wal` is local scratch state and is intentionally ignored.

## Boundary

- Lab-only application prototype surface.
- Not a canonical language example.
- Not public runtime, package, release, production, or demo authority.

## Local Checks

```bash
cd todolist
ruby todo.rb help
ruby todo.rb repl
```
