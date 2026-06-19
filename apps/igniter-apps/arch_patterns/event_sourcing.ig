module ArchPatternsEventSourcing
import ArchPatternsTypes

-- ============================================================
-- Pattern 1: Event Sourcing
-- ============================================================
-- State is NEVER stored directly. It is always derived by
-- replaying ("folding") events from the beginning.
-- This is the purest possible fit for Igniter's immutable model.
-- ============================================================

contract ApplyEvent {
  input state : AccountState
  input event : DomainEvent

  -- Apply a single event to the current state
  compute new_balance = if event.kind == "Deposited" {
    state.balance + event.amount
  } else {
    if event.kind == "Withdrawn" {
      state.balance - event.amount
    } else {
      state.balance
    }
  }

  compute new_status = if event.kind == "AccountOpened" {
    "active"
  } else {
    if event.kind == "Frozen" {
      "frozen"
    } else {
      if event.kind == "Unfrozen" {
        "active"
      } else {
        if event.kind == "Closed" {
          "closed"
        } else {
          state.status
        }
      }
    }
  }

  compute new_state = {
    account_id: state.account_id,
    status: new_status,
    balance: new_balance,
    version: state.version + 1
  }

  output new_state : AccountState
}

contract ReplayEvents3 {
  input initial : AccountState
  input e0 : DomainEvent
  input e1 : DomainEvent
  input e2 : DomainEvent

  -- Manual 3-event replay (Igniter lacks fold/reduce)
  compute s1 = call_contract("ApplyEvent", initial, e0)
  compute s2 = call_contract("ApplyEvent", s1, e1)
  compute s3 = call_contract("ApplyEvent", s2, e2)

  output s3 : AccountState
}

contract ReplayEvents5 {
  input initial : AccountState
  input e0 : DomainEvent
  input e1 : DomainEvent
  input e2 : DomainEvent
  input e3 : DomainEvent
  input e4 : DomainEvent

  compute s1 = call_contract("ApplyEvent", initial, e0)
  compute s2 = call_contract("ApplyEvent", s1, e1)
  compute s3 = call_contract("ApplyEvent", s2, e2)
  compute s4 = call_contract("ApplyEvent", s3, e3)
  compute s5 = call_contract("ApplyEvent", s4, e4)

  output s5 : AccountState
}
