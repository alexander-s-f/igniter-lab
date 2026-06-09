# Lab Doc: Rust Compiler Parser Non-Progress and Subprocess Timeout Hardening v0

**Card:** LAB-COMPILER-LIVENESS-P5
**Track:** lab-rust-compiler-parser-nonprogress-and-subprocess-timeout-hardening-v0
**Route:** EXPERIMENTAL / LAB-ONLY / PARSER-HARDENING
**Authority:** Lab evidence only. Not canon. Not production.
**Date:** 2026-06-09
**Depends:** LAB-COMPILER-LIVENESS-P1 through P4
**Status:** Closed — 46/46 PASS

---

## 1. Purpose

Close the compiler hang class first observed during LAB-VM-MAP-P1: malformed declarations inside Igniter source files caused the parser to loop infinitely rather than fail with diagnostics. This lab proves:

1. **Malformed declarations fail closed** — `output result`, `output result:`, `type Foo { x }`, `type Foo { x: }` all produce `status: "error"` with an OOF-P1 diagnostic instead of hanging.
2. **Parser always makes token progress** — after any error, at least one token is consumed before the next loop iteration, so body-parsing loops cannot cycle.
3. **Proof runner timeout kills subprocesses** — `BoundedCommand` (the Ruby verify runner's subprocess wrapper) now has a deadline thread that sends SIGTERM then SIGKILL to the compiler child if it exceeds the timeout.
4. **No orphan processes** — repeated malformed compilations leave the process table clean.
5. **stdout/stderr bounded** — all malformed inputs produce ≤ 64 KB of output, and output is valid JSON.

---

## 2. Root Cause Analysis

### 2.1 `peek_type` behavior past EOF sentinel

The Igniter parser is array-based: tokens are stored in `Vec<Token>`, with an explicit `Eof` sentinel appended by the lexer. The parser tracks position via `self.pos`.

**Pre-P5 `peek_type`:**
```rust
fn peek_type(&self, t_type: TokenType) -> bool {
    self.current().map_or(false, |t| t.token_type == t_type)
}
```

When `pos >= tokens.len()` (past the EOF sentinel), `current()` returns `None`. `map_or(false, ...)` returns `false` for ALL queries including `Eof`. Therefore every `while !peek_type(Eof)` loop became infinite when a parser advanced past the EOF sentinel.

**How the EOF sentinel was consumed:** `expect_type()` advances past ANY mismatched token unconditionally. In malformed input, inner parsers consumed `}` tokens via `expect_type(Colon)`, leaving subsequent `expect_type(RBrace)` to consume the explicit EOF sentinel. After that, `advance()` was a no-op and `peek_type(Eof)` returned false.

**Concrete hang path for `output result` (missing annotation):**

```
tokens: [Keyword("output"), Ident("result"), RBrace("}"), Eof]
parse_output_decl():
  name_token() → Ok("result"), pos=2
  expect_type(Colon) → current=RBrace, mismatch → advance → pos=3 (consumed "}")
  returns Err("Expected Colon")
                                  ↑ but this propagated up as None to the body loop
outer body loop: peek_type(RBrace) → current=Eof → false
                 peek_type(Eof)    → current=Eof → TRUE (Eof IS Eof)
                 loop exits... 
                 
WAIT — actually the loop exits here due to peek_type(Eof) via the correct mechanism.
BUT: the old peek_type returned false for Eof when current()=None (past the sentinel).
```

The actual hang path is when `expect_type` consumes the explicit `Eof` sentinel itself:

```
tokens: [Keyword("output"), Ident("result"), Eof]  (no closing brace)
parse_output_decl():
  name_token() → Ok("result"), pos=2
  expect_type(Colon) → current=Eof, mismatch → advance → pos=3 (past array)
outer body loop: current()=None → peek_type(RBrace)=false, peek_type(Eof)=false
  → loop never exits
```

### 2.2 P5 Fix: `peek_type` EOF sentinel

```rust
fn peek_type(&self, t_type: TokenType) -> bool {
    // LAB-COMPILER-LIVENESS-P5: treat "past end of token stream" as EOF so every
    // `while !peek_type(Eof)` loop terminates even when inner parsers over-consume
    // past the explicit EOF sentinel via expect_type or advance().
    match self.current() {
        None => t_type == TokenType::Eof,
        Some(t) => t.token_type == t_type,
    }
}
```

This is a single-line semantic change. When `current()` returns `None`, `peek_type(Eof)` returns `true`. Every `while !peek_type(Eof)` loop now terminates unconditionally when the parser has exhausted the token stream.

### 2.3 `parse_body_decl_with_recovery` helper

Recovery wrapper for `output` and `compute` declarations. When the inner parser returns `Err`:

1. If no tokens were consumed (rare), advance at least one to guarantee progress.
2. Emit an OOF-P1 diagnostic with the keyword location.
3. Call `skip_until_body_boundary()` to advance to the next declaration boundary.

This ensures that even with the EOF fix, a malformed declaration skips gracefully to the next recoverable point rather than leaving the parser in an unknown state.

### 2.4 `parse_type_decl` field recovery

Pre-P5, `parse_type_decl` used `?`-propagation for field parsing:

```rust
let fname = self.name_token()?;
self.expect_type(TokenType::Colon)?;
let ftype = self.parse_type_ref()?;
```

This propagated `Err` up to the caller — which handled it via `.ok()` in `parse_body_decl`. The outer body loop then saw `None` and looped again from the same position, hanging.

P5 replaces each `?`-call with explicit match-on-Err that emits OOF-P1 and skips to the next field boundary:

```rust
let fname = match self.name_token() {
    Ok(n) => n,
    Err(_) => { /* emit diagnostic, advance, continue */ }
};
if !self.peek_type(TokenType::Colon) {
    /* emit diagnostic, skip to boundary, continue */
}
self.advance(); // consume ':'
let ftype = match self.parse_type_ref() {
    Ok(t) => t,
    Err(msg) => { /* emit diagnostic, skip to boundary, continue */ }
};
```

---

## 3. Subprocess Timeout Hardening

### 3.1 Pre-P5 BoundedCommand

```ruby
class BoundedCommand
  def initialize(cmd)
    @stdout, @stderr, st = Open3.capture3(*cmd)
    @exit_code = st.exitstatus
  end
end
```

`Open3.capture3` has no timeout. If the compiler hangs, the Ruby verify script hangs indefinitely.

### 3.2 P5 BoundedCommand

Uses `Process.spawn` with explicit IO pipes and a timeout thread:

```ruby
pid = Process.spawn(*cmd, out: w_out, err: w_err)
killer_thread = Thread.new do
  sleep timeout_secs
  begin
    Process.kill('TERM', pid)
    sleep 0.5
    Process.kill('KILL', pid)
  rescue Errno::ESRCH
    # Process already exited.
  end
  @timed_out = true
end
@stdout = r_out.read(STDOUT_CAP + 1) || ''
@stderr = r_err.read(STDERR_CAP + 1) || ''
_, status = Process.waitpid2(pid)
killer_thread.kill; killer_thread.join
```

Key properties:
- `STDOUT_CAP = 64 KB` — limits memory consumption from runaway output
- `timeout_secs: 15` default for all real compiler calls
- `timed_out` flag: `true` only if the timeout fired
- Killer thread is always joined (no orphan threads)
- `SIGTERM` first (graceful), then `SIGKILL` after 500ms (force)

### 3.3 Process count invariant

Verified by P5-I: `pgrep -f igniter_compiler` count before and after 5 malformed compilations is identical. No process accumulation.

---

## 4. What P5 Does NOT Do

- **No language semantic changes** — the parser recovers silently; it does not change what valid programs mean.
- **No hiding of parser bugs via timeout** — the root hang class is fixed at the source (`peek_type` + recovery). The timeout is a defense-in-depth backstop, not the primary fix.
- **No new compiler error codes** — OOF-P1 (existing parse error code) is used.
- **No runtime/VM changes** — parser-only.
- **No canon impact** — lab-only changes to the lab compiler.

---

## 5. Proof Matrix

| Section | Description | Checks |
|---------|-------------|--------|
| P5-A | Build | 1 |
| P5-B | `output result` (no annotation) fails closed | 4 |
| P5-C | `output result:` (colon, no type) fails closed | 4 |
| P5-D | `type Foo { x }` (no colon) fails closed | 4 |
| P5-E | `type Foo { x: }` (no type) fails closed | 4 |
| P5-F | Multiple malformed: recovery continues | 4 |
| P5-G | Well-formed regression | 3 |
| P5-H | BoundedCommand timeout kills subprocess | 4 |
| P5-I | Process count invariant | 1 |
| P5-J | stdout bounded + machine-readable | 10 |
| P5-K | peek_type EOF fix confirmed | 2 |
| P5-L | P4 regression (canonical fixtures) | 5 |
| **Total** | | **46** |

```
ruby verify_liveness_p5.rb    46/46 PASS
ruby verify_liveness_p4.rb    40/40 PASS  (backward compat confirmed)
```

---

## 6. Files Changed

### `igniter-lab/igniter-compiler/src/parser.rs`

| Change | Location | Description |
|--------|----------|-------------|
| `peek_type` fix | `fn peek_type` | Returns `true` for `Eof` when `current()` is `None` (past token array end) |
| `parse_body_decl_with_recovery` | New helper | Wraps body-decl parsers; on `Err`: advance, emit OOF-P1, skip to boundary |
| `parse_body_decl` — output | `"output" =>` arm | Now uses `parse_body_decl_with_recovery` |
| `parse_body_decl` — compute | `"compute" =>` arm | Now uses `parse_body_decl_with_recovery` |
| `parse_type_decl` | field loop | Explicit `match`-on-`Err` for name, colon, type; emits OOF-P1; skips to boundary |

### New fixtures

| File | Expected result |
|------|----------------|
| `fixtures/liveness_p5_output_no_annotation.ig` | status=error, OOF-P1 |
| `fixtures/liveness_p5_output_colon_no_type.ig` | status=error, OOF-P1 |
| `fixtures/liveness_p5_type_field_no_colon.ig` | status=error, OOF-P1 |
| `fixtures/liveness_p5_type_field_no_type.ig` | status=error, OOF-P1 |
| `fixtures/liveness_p5_multiple_malformed.ig` | status=error, ≥2 OOF-P1 |
| `fixtures/liveness_p5_well_formed.ig` | status=ok, no diagnostics |

### New scripts / docs

| File | Description |
|------|-------------|
| `verify_liveness_p5.rb` | 46-check proof script with BoundedCommand timeout |
| `lab-docs/lang/lab-rust-compiler-parser-nonprogress-and-subprocess-timeout-hardening-v0.md` | This doc |
| `.agents/work/cards/lang/LAB-COMPILER-LIVENESS-P5.md` | Agent card |

---

## 7. Authority and Boundary

```
authority:                     lab_only_p5_parser_hardening
new_OOF_codes:                 NONE (OOF-P1 pre-existing)
canon_impact:                  NONE
production_impact:             NONE
VM_change:                     NONE
language_semantics_change:     NONE
grammar_change:                NONE
new_fatal_limits:              NONE
igniter-org_change:            NONE
```

---

## 8. Next Route

**P5 closes the compiler hang class for the identified patterns.** Future work candidates:

1. **Complete recovery for all body-decl keywords** — `input`, `read`, `snapshot`, `window`, `escape`, `stream`, etc. currently use `.ok()` fallback. With the `peek_type` fix, the outer loop never hangs (the `_ =>` arm in `parse_body_decl` advances any unrecognized token). But OOF-P1 diagnostics are not emitted for failed `input`/`read` parses. A future card could extend `parse_body_decl_with_recovery` to all keywords.

2. **E-COMPILER-CYCLE instrumentation** — classified LOW risk by P4; trigger condition: grammar changes enabling form-calls-form.

3. **BoundedCommand for igc VM runner** — similar timeout hardening for the VM subprocess in future VM-adjacent proof scripts.

4. **Promote `parse_body_decl_with_recovery` to P5 canon** — if the pattern proves useful outside lab, a PROP could generalize it.
