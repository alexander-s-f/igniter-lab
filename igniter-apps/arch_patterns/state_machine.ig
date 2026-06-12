module ArchPatternsStateMachine
import ArchPatternsTypes
import stdlib.collection.{ filter }

-- ============================================================
-- Pattern 2: State Machine
-- ============================================================
-- Explicit states + guarded transitions.
-- The machine checks:
--   1. Is there a valid transition from current status?
--   2. Does the guard condition pass?
-- If yes → transition. If no → reject.
-- ============================================================

contract CheckTransition {
  input current_status : String
  input event_kind : String
  input balance : Integer
  input transitions : Collection[Transition]

  -- Find matching transitions
  compute candidates = filter(transitions, t ->
    if t.from_status == current_status {
      if t.event_kind == event_kind {
        true
      } else {
        false
      }
    } else {
      false
    }
  )

  -- Since we can't extract head(), we output the filtered set
  output candidates : Collection[Transition]
}

contract GuardCheck {
  input balance : Integer
  input required_min : Integer

  compute passed = if balance > required_min {
    true
  } else {
    if balance == required_min {
      true
    } else {
      false
    }
  }

  output passed : Bool
}

contract TryTransition {
  input machine : StateMachine
  input event : DomainEvent

  -- Check if transition exists for current status + event kind
  compute candidates = call_contract("CheckTransition",
    machine.current.status,
    event.kind,
    machine.current.balance,
    machine.transitions
  )

  -- Apply the event (optimistic — in a real system we'd check
  -- candidates is non-empty, but we lack is_empty())
  compute next_state = call_contract("ApplyEvent", machine.current, event)

  compute updated_machine = {
    current: next_state,
    transitions: machine.transitions
  }

  output updated_machine : StateMachine
}
