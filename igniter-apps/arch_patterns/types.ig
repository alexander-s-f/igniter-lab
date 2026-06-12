module ArchPatternsTypes

-- ============================================================
-- Architectural Patterns: Core Domain Types
-- ============================================================
-- Domain: Banking Account
-- Patterns: Event Sourcing, State Machine, Middleware Pipeline
-- ============================================================

-- ── Event Sourcing ──────────────────────────────────────────

type DomainEvent {
  seq : Integer
  kind : String
  -- kind = "AccountOpened" | "Deposited" | "Withdrawn"
  --      | "Frozen" | "Unfrozen" | "Closed"
  amount : Integer
  timestamp : Integer
  actor : String
}

type EventLog {
  account_id : String
  events : Collection[DomainEvent]
}

-- ── State Machine ───────────────────────────────────────────

type AccountState {
  account_id : String
  status : String
  -- status = "pending" | "active" | "frozen" | "closed"
  balance : Integer
  version : Integer
}

type Transition {
  from_status : String
  to_status : String
  event_kind : String
  guard_min_balance : Integer
}

type StateMachine {
  current : AccountState
  transitions : Collection[Transition]
}

-- ── Middleware Pipeline ──────────────────────────────────────

type Command {
  kind : String
  -- kind = "deposit" | "withdraw" | "freeze" | "close"
  amount : Integer
  actor : String
  timestamp : Integer
}

type PipelineContext {
  command : Command
  account : AccountState
  rejected : Bool
  reject_reason : String
  audit_trail : Collection[String]
}
