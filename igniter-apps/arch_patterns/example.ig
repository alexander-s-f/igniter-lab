module ArchPatternsExample
import ArchPatternsTypes
import ArchPatternsEventSourcing
import ArchPatternsStateMachine
import ArchPatternsPipeline
import stdlib.collection.{ append }

-- ============================================================
-- Full Integration Example
-- ============================================================
-- Scenario: Open account → Deposit → Withdraw → Attempt
--           overdraft (rejected by pipeline) → Freeze
-- ============================================================

contract BuildTransitionTable {
  compute t0 = { from_status: "pending", to_status: "active", event_kind: "AccountOpened", guard_min_balance: 0 }
  compute t1 = { from_status: "active", to_status: "active", event_kind: "Deposited", guard_min_balance: 0 }
  compute t2 = { from_status: "active", to_status: "active", event_kind: "Withdrawn", guard_min_balance: 0 }
  compute t3 = { from_status: "active", to_status: "frozen", event_kind: "Frozen", guard_min_balance: 0 }
  compute t4 = { from_status: "frozen", to_status: "active", event_kind: "Unfrozen", guard_min_balance: 0 }
  compute t5 = { from_status: "active", to_status: "closed", event_kind: "Closed", guard_min_balance: 0 }

  compute c0 = call_contract("append", t0, t1)
  compute c1 = call_contract("append", c0, t2)
  compute c2 = call_contract("append", c1, t3)
  compute c3 = call_contract("append", c2, t4)
  compute c4 = call_contract("append", c3, t5)

  output c4 : Collection[Transition]
}

contract RunFullScenario {
  -- ── Step 0: Genesis state ──
  compute genesis = {
    account_id: "ACC-001",
    status: "pending",
    balance: 0,
    version: 0
  }

  -- ── Step 1: Event Sourcing — replay 5 events ──
  compute ev_open = { seq: 1, kind: "AccountOpened", amount: 0, timestamp: 1000, actor: "system" }
  compute ev_deposit = { seq: 2, kind: "Deposited", amount: 5000, timestamp: 1001, actor: "user" }
  compute ev_withdraw = { seq: 3, kind: "Withdrawn", amount: 1500, timestamp: 1002, actor: "user" }
  compute ev_deposit2 = { seq: 4, kind: "Deposited", amount: 2000, timestamp: 1003, actor: "user" }
  compute ev_freeze = { seq: 5, kind: "Frozen", amount: 0, timestamp: 1004, actor: "admin" }

  compute final_state = call_contract("ReplayEvents5", genesis, ev_open, ev_deposit, ev_withdraw, ev_deposit2, ev_freeze)
  -- Expected: status="frozen", balance=5500, version=5

  -- ── Step 2: State Machine — verify transition table ──
  compute transitions = call_contract("BuildTransitionTable")
  compute machine = {
    current: final_state,
    transitions: transitions
  }

  -- Try to unfreeze
  compute ev_unfreeze = { seq: 6, kind: "Unfrozen", amount: 0, timestamp: 1005, actor: "admin" }
  compute machine_after = call_contract("TryTransition", machine, ev_unfreeze)
  -- Expected: status="active", version=6

  -- ── Step 3: Pipeline — validate a withdraw command ──
  compute withdraw_cmd = { kind: "withdraw", amount: 3000, actor: "user", timestamp: 1006 }
  compute empty_trail = call_contract("append", "pipeline:start", "pipeline:init")

  compute pipeline_ctx = {
    command: withdraw_cmd,
    account: machine_after.current,
    rejected: false,
    reject_reason: "",
    audit_trail: empty_trail
  }

  compute validated = call_contract("RunPipeline", pipeline_ctx)
  -- Expected: rejected=false (balance 5500 > 3000)

  -- ── Step 4: Pipeline — attempt overdraft ──
  compute overdraft_cmd = { kind: "withdraw", amount: 99999, actor: "user", timestamp: 1007 }

  compute overdraft_ctx = {
    command: overdraft_cmd,
    account: machine_after.current,
    rejected: false,
    reject_reason: "",
    audit_trail: empty_trail
  }

  compute overdraft_result = call_contract("RunPipeline", overdraft_ctx)
  -- Expected: rejected=true, reason="insufficient balance"

  compute unfrozen_state = machine_after.current

  output final_state : AccountState
  output unfrozen_state : AccountState
  output validated : PipelineContext
  output overdraft_result : PipelineContext
}
