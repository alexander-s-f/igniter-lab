# LAB-ACTS-AS-TBACKEND-CORE-RAILS-REFRESH-P1 — lock core connector + port Rails extension to new API

Status: CLOSED
Lane: tbackend / ruby connector / business pressure
Type: implementation
Delegation code: OPUS-ACTS-AS-TBACKEND-CORE-RAILS-REFRESH-P1
Date: 2026-07-01
Skill: idd-agent-protocol

## Context

`acts-as-tbackend` has just been refreshed from an old sketch into a production-shaped Ruby connector core:

- `Connection` — one persistent framed socket, protocol, token, reconnect, rich status mapping.
- `Pool` — N persistent connections via `connection_pool`.
- `Client` — app facade with circuit breaker.
- `Fact` — deterministic `derive_id` and fact builder.
- `Config` — ENV/default config.
- gemspec — `acts-as-tbackend` v0.2.0.

Curator spot-checks passed:

```text
ruby -c lib/**/*.rb                         OK
ruby -Ilib -e 'require "acts_as_tbackend"'  OK
client.ping without daemon                  {:status=>"unavailable"} soft result
circuit breaker smoke                       unavailable -> circuit_open
Fact.derive_id                              deterministic µs-epoch token
gem build acts-as-tbackend.gemspec          OK
```

But the repo still has old application-layer files:

- `lib/acts_as_tbackend/extension.rb`
- `lib/acts_as_tbackend/shadow_comparison.rb`
- `verify_shadow.rb`
- `demo.rb`

Those still reference old APIs such as `ActsAsTbackend.enabled?`, `ActsAsTbackend.client(host, port)`,
`write_fact`, `query_scope`, and async queue helpers. Top-level `require "acts_as_tbackend"` no longer loads
them, which keeps the new core clean, but Rails integration is not refreshed yet.

Also note: unrelated command-center work may be in the worktree (`bin/igniter`, workspace P3). **Do not touch
that.** This card is strictly under:

```text
runtime/acts-as-tbackend/
```

## Goal

Make the `acts-as-tbackend` refresh internally coherent:

1. Add focused tests for the new core connector.
2. Port the Rails extension layer to the new core API.
3. Keep down-daemon behavior non-fatal for Rails shadow writes.
4. Keep deterministic idempotency through `Fact.derive_id`.
5. Keep shadow comparison/demo either ported or explicitly marked as legacy/follow-up without breaking core load.

This is **not** the load-test card. Do not start lab machines or Tailscale. Do not run production traffic.

## Verify first

Read live files:

- `runtime/acts-as-tbackend/README.md`
- `runtime/acts-as-tbackend/acts-as-tbackend.gemspec`
- `runtime/acts-as-tbackend/lib/acts_as_tbackend.rb`
- `runtime/acts-as-tbackend/lib/acts_as_tbackend/{connection,pool,client,fact,config,circuit_breaker,version}.rb`
- `runtime/acts-as-tbackend/lib/acts_as_tbackend/extension.rb`
- `runtime/acts-as-tbackend/lib/acts_as_tbackend/shadow_comparison.rb`
- `runtime/acts-as-tbackend/verify_shadow.rb`
- `runtime/acts-as-tbackend/demo.rb`

Also verify the live TBackend daemon protocol from `igniter-tbackend` source if needed:

- ops expected by the new core: `ping`, `write_fact_once`, `latest_for`, `facts_for`, `facts_by_seq`.
- legacy ops such as `query_scope` must not be newly depended on.

## Required decisions

### Result shape

The new core currently returns plain Ruby hashes:

```ruby
{ ok:, status:, committed:, retryable:, response:, error: }
```

Decide explicitly:

- keep hash API for v0 and document `result[:status]`, or
- introduce a tiny `Result` object with `ok?`, `status`, `retryable?`.

Do not leave docs/tests half-object, half-hash. Curator preference: **keep hash API for this card** unless a
tiny object clearly reduces confusion without widening scope.

### Extension API

Port `extension.rb` so it no longer calls old APIs:

- no `ActsAsTbackend.enabled?` unless reintroduced deliberately in `Config`;
- no `ActsAsTbackend.client(host, port)`;
- no `write_fact`;
- no `query_scope`;
- writes use `Fact.derive_id` + `Fact.build` + `client.write_fact_once_safe`;
- reads use `latest_for`, `facts_for`, and/or `facts_by_seq`.

Down daemon must stay non-fatal: callbacks should log/return soft failure, not raise into the Rails request
path by default.

### Async / background path

If the old async queue/Sidekiq sketch is too wide to port now, choose one clean v0:

- synchronous shadow write with soft result; or
- explicit hook method that apps can call from their own job; or
- keep async as a clear follow-up.

Do not leave references to removed `enqueue_job`.

## Suggested tests

Add a lightweight Ruby test suite under `runtime/acts-as-tbackend/test/` or `spec/` using stdlib `minitest`
unless the repo already has a test convention.

Recommended tests:

1. `Fact.derive_id` is deterministic and colon-safe for `Time`.
2. `Fact.build` emits required fields and omits `value_hash`.
3. `Client#ping` against a closed port returns `status: "unavailable"` and does not raise.
4. Circuit breaker opens after threshold and returns `status: "circuit_open"`.
5. `Connection#write_fact_once` maps a fake successful response to `committed_acked`.
6. `Connection#write_fact_once` maps `idempotent_replay`.
7. `Connection#write_fact_once` maps `duplicate_fact_id_conflict`.
8. Extension builds a deterministic fact envelope for a model-like object without requiring ActiveRecord if
   possible, or with a tiny fake if AR is unavailable.

Use fake sockets / monkeypatching where needed; do not require a live daemon for unit tests.

## Required commands

Run from `runtime/acts-as-tbackend`:

```text
ruby -c lib/acts_as_tbackend.rb
for f in lib/acts_as_tbackend/*.rb; do ruby -c "$f"; done
ruby -Ilib -e 'require "acts_as_tbackend"; p ActsAsTbackend.client.ping'
gem build acts-as-tbackend.gemspec
```

If you add `test/`:

```text
ruby -Ilib:test test/*_test.rb
```

Remove any generated `.gem` artifact after the build smoke unless the repo already tracks release artifacts.

Also run:

```text
git diff --check -- runtime/acts-as-tbackend
```

## Acceptance

- [ ] New core has focused Ruby tests.
- [ ] `extension.rb` no longer references removed old APIs.
- [ ] No `enabled?`, `enqueue_job`, `client(host, port)`, `write_fact`, or `query_scope` references remain in
      active loaded code unless explicitly reintroduced and tested.
- [ ] Rails callback write path uses `Fact.derive_id` + `write_fact_once_safe`.
- [ ] Down daemon remains soft/non-fatal by default.
- [ ] Result shape is consistent in README/tests/code.
- [ ] `require "acts_as_tbackend"` loads cleanly.
- [ ] `gem build` succeeds.
- [ ] Generated `.gem` artifact is removed.
- [ ] No changes outside `runtime/acts-as-tbackend/`.
- [ ] `git diff --check -- runtime/acts-as-tbackend` clean.

## Non-goals

- No load test / rpm claim.
- No lab machines / Tailscale.
- No production deploy.
- No TBackend daemon changes.
- No command-center workspace changes.
- No SparkCRM code changes.

## Likely next card

`LAB-ACTS-AS-TBACKEND-LOCAL-DAEMON-LOAD-P2` — start local release `tbackend`, run pooled `write_fact_once`
driver, measure 5-8k rpm and ceiling with p50/p99/error-rate/backpressure.

## Closing report

**CLOSED 2026-07-01.** The refresh is internally coherent: the new core is tested, the Rails extension is
ported to the new API, and legacy files are load-isolated and banner-marked.

### Decisions taken
- **Result shape: hash** (curator preference) — `{ ok:, status:, committed:, retryable:, response:, error: }`,
  documented in README and asserted in tests. No half-object/half-hash.
- **Async v0: synchronous soft mirror.** `after_commit` → `Mirror.mirror!` → `client.write_fact_once_safe`
  (pooled, circuit-broken, soft/non-fatal). No `enqueue_job`. For heavy paths, apps call the public
  `record.tbackend_fact(...)` from their own background job. Async queue = explicit follow-up, not dangling.
- **`enabled?` reintroduced deliberately in `Config`** (`config.enabled`, ENV `TBACKEND_ENABLED`, default on) +
  `ActsAsTbackend.enabled?`; tested (`Mirror.mirror!` returns `status: "disabled"` when off).
- **Testability without AR:** record→fact building lives in plain-Ruby `ActsAsTbackend::Mirror` (no
  ActiveSupport); `Extension` (AR concern) only wires callbacks and delegates. Core entry stays AR-free.

### Changes (all under `runtime/acts-as-tbackend/`)
- Added `lib/acts_as_tbackend/mirror.rb` (plain-Ruby record→fact mirror + soft write).
- Ported `lib/acts_as_tbackend/extension.rb` → `acts_as_tbackend` macro (store/only/except), after_commit
  create/update/destroy via `previously_new_record?`, class read API `tbackend_history`/`tbackend_latest_for`/
  `tbackend_facts_by_seq`, self-install via `ActiveSupport.on_load(:active_record)`. Removed `write_fact`,
  `query_scope`, `client(host, port)`, `enqueue_job`, `host`/`port` options, and the per-write causation read.
- `Config#enabled` + `ActsAsTbackend.enabled?`; entry requires `mirror`.
- Legacy banners on `shadow_comparison.rb`, `verify_shadow.rb`, `demo.rb` (not loaded by the core entry).
- Added `test/` (minitest): `fact_test`, `connection_test`, `client_test`, `mirror_test` (FakeSocket +
  ephemeral-closed-port helpers; no live daemon).

### Verification (from `runtime/acts-as-tbackend/`)
```text
ruby -c lib/**                                    all Syntax OK
ruby -Ilib -e require + client.ping               "unavailable" (soft, loads clean, AR-free)
require acts_as_tbackend/extension                loads (self-install hook registered)
ruby -Ilib:test -e 'ARGV.each { |f| require File.expand_path(f) }' test/*_test.rb
                                                    12 runs, 37 assertions, 0 failures, 0 errors, 0 skips
gem build acts-as-tbackend.gemspec                Successfully built 0.2.0 (artifact removed)
grep enqueue_job|query_scope|client(|write_fact   clean in loaded code
git diff --check -- runtime/acts-as-tbackend      clean (exit 0)
```

### Acceptance — all met
Core tests ✅ · extension no old APIs ✅ · no removed-API refs in loaded code (enabled? reintroduced+tested) ✅ ·
callback path uses `Fact.derive_id` + `write_fact_once_safe` ✅ · down-daemon soft/non-fatal ✅ · result shape
consistent ✅ · `require` clean ✅ · `gem build` ✅ · `.gem` removed ✅ · scope confined to `runtime/acts-as-tbackend/`
✅ · `git diff --check` clean ✅. Did not touch command-center/`bin/igniter`, SparkCRM, or the daemon.

### Follow-up (not this card)
- Async queue path (Sidekiq/thread) on the new core, if wanted beyond the app-owned-job hook.
- Port `shadow_comparison.rb` / `demo.rb` / `verify_shadow.rb` to the new core (currently legacy-marked).
- **`LAB-ACTS-AS-TBACKEND-LOCAL-DAEMON-LOAD-P2`** — local live daemon + pooled driver, prove 5-8k rpm + ceiling.
