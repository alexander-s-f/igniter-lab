module Lab.OutcomeVariant.BindingCollision

-- LAB-OUTCOME-VARIANT-P3: Proves the VM compiler handles the case where a
-- match arm binding name equals the enclosing compute node name.
--
-- Before the fix (LAB-OUTCOME-VARIANT-P3), the following pattern panicked:
--
--   compute attempt: Integer = match outcome {
--     ConfirmedFailed { attempt } => attempt
--   }
--
-- The arm binding cleanup `remove("attempt")` deleted the compute node's own
-- register entry, causing an unwrap() panic at the OP_STORE_REG site.
--
-- After the fix: lexical scoping — the outer register is saved before the
-- binding is inserted and restored after the arm body compiles.
--
-- Authority: LAB-ONLY. Not canon. Not production. No Outcome[T,E]. No taxonomy.
-- Depends: LAB-OUTCOME-VARIANT-P2, compiler.rs scoped-shadowing fix.

variant CollisionOutcome {
  HasAttempt    { attempt: Integer }
  HasObservedAt { observed_at: String }
  HasBoth       { attempt: Integer, observed_at: String }
  Neither       {}
}

-- ── Case 1: Integer compute name == binding name ─────────────────────────────
-- `compute attempt` contains a match arm binding named `attempt`.
-- The fix ensures the compute node register is restored after the arm exits.

contract ExtractAttemptDirect {
  input outcome: CollisionOutcome
  compute attempt: Integer = match outcome {
    HasAttempt    { attempt }    => attempt
    HasBoth       { attempt }    => attempt
    HasObservedAt {}             => 0
    Neither       {}             => 0
  }
  output attempt: Integer
}

-- ── Case 2: String compute name == binding name ──────────────────────────────
-- `compute observed_at` contains a match arm binding named `observed_at`.

contract ExtractObservedAtDirect {
  input outcome: CollisionOutcome
  compute observed_at: String = match outcome {
    HasObservedAt { observed_at } => observed_at
    HasBoth       { observed_at } => observed_at
    HasAttempt    {}              => "not_applicable"
    Neither       {}              => "not_applicable"
  }
  output observed_at: String
}

-- ── Case 3: Collision arm + non-collision arm in same match ──────────────────
-- One arm binds a name that collides; another arm binds a different name.
-- The collision arm must not corrupt the scope for subsequent arms.

contract ExtractMixed {
  input outcome: CollisionOutcome
  compute attempt: Integer = match outcome {
    HasAttempt    { attempt }    => attempt
    HasBoth       { attempt }    => attempt
    HasObservedAt {}             => 0
    Neither       {}             => 0
  }
  compute label: String = match outcome {
    HasAttempt    {}             => "has_attempt"
    HasObservedAt {}             => "has_observed_at"
    HasBoth       {}             => "has_both"
    Neither       {}             => "neither"
  }
  output attempt: Integer
}

-- ── Case 4: Multiple arms sharing the same binding name ──────────────────────
-- `attempt` binding appears in HasAttempt AND HasBoth arms.
-- Each arm should independently shadow and restore without confusion.

contract ExtractAttemptMultiArm {
  input outcome: CollisionOutcome
  compute attempt: Integer = match outcome {
    HasAttempt { attempt }    => attempt
    HasBoth    { attempt }    => attempt
    HasObservedAt {}           => 99
    Neither {}                 => 99
  }
  output attempt: Integer
}

-- ── Case 5: Non-colliding case still works (regression guard) ────────────────
-- Compute name `result_val` differs from binding `attempt` — this always worked.

contract ExtractAttemptSafe {
  input outcome: CollisionOutcome
  compute result_val: Integer = match outcome {
    HasAttempt { attempt }    => attempt
    HasBoth    { attempt }    => attempt
    HasObservedAt {}           => 0
    Neither {}                 => 0
  }
  output result_val: Integer
}

-- ── Case 6: Label routing (no collision) ────────────────────────────────────
-- Arm-label routing with no bindings — sanity check.

contract RouteCollision {
  input outcome: CollisionOutcome
  compute action: String = match outcome {
    HasAttempt    {} => "has_attempt"
    HasObservedAt {} => "has_observed_at"
    HasBoth       {} => "has_both"
    Neither       {} => "neither"
  }
  output action: String
}
