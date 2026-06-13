module ArchPatternsPipeline
import ArchPatternsTypes
import stdlib.collection.{ append }

-- ============================================================
-- Pattern 3: Middleware Pipeline
-- ============================================================
-- Each "middleware" is a contract that receives a PipelineContext,
-- performs validation/enrichment, and returns a modified context.
-- Middlewares are chained sequentially.
-- If any middleware sets rejected=true, subsequent middlewares
-- should short-circuit (check ctx.rejected first).
-- ============================================================

contract MwValidateAmount {
  input ctx : PipelineContext

  -- Middleware 1: Reject negative or zero amounts for deposit/withdraw
  compute should_check = if ctx.command.kind == "deposit" {
    true
  } else {
    if ctx.command.kind == "withdraw" {
      true
    } else {
      false
    }
  }

  compute is_invalid = if should_check {
    if ctx.command.amount < 1 {
      true
    } else {
      false
    }
  } else {
    false
  }

  compute new_trail = append(ctx.audit_trail, "mw:validate_amount")

  compute result = if ctx.rejected {
    ctx
  } else {
    if is_invalid {
      {
        command: ctx.command,
        account: ctx.account,
        rejected: true,
        reject_reason: "amount must be positive",
        audit_trail: new_trail
      }
    } else {
      {
        command: ctx.command,
        account: ctx.account,
        rejected: false,
        reject_reason: "",
        audit_trail: new_trail
      }
    }
  }

  output result : PipelineContext
}

contract MwCheckFrozen {
  input ctx : PipelineContext

  compute new_trail = append(ctx.audit_trail, "mw:check_frozen")

  compute is_frozen = if ctx.account.status == "frozen" {
    true
  } else {
    false
  }

  compute result = if ctx.rejected {
    ctx
  } else {
    if is_frozen {
      {
        command: ctx.command,
        account: ctx.account,
        rejected: true,
        reject_reason: "account is frozen",
        audit_trail: new_trail
      }
    } else {
      {
        command: ctx.command,
        account: ctx.account,
        rejected: false,
        reject_reason: "",
        audit_trail: new_trail
      }
    }
  }

  output result : PipelineContext
}

contract MwCheckBalance {
  input ctx : PipelineContext

  compute new_trail = append(ctx.audit_trail, "mw:check_balance")

  compute insufficient = if ctx.command.kind == "withdraw" {
    if ctx.account.balance < ctx.command.amount {
      true
    } else {
      false
    }
  } else {
    false
  }

  compute result = if ctx.rejected {
    ctx
  } else {
    if insufficient {
      {
        command: ctx.command,
        account: ctx.account,
        rejected: true,
        reject_reason: "insufficient balance",
        audit_trail: new_trail
      }
    } else {
      {
        command: ctx.command,
        account: ctx.account,
        rejected: false,
        reject_reason: "",
        audit_trail: new_trail
      }
    }
  }

  output result : PipelineContext
}

contract RunPipeline {
  input ctx : PipelineContext

  -- Chain all middlewares sequentially
  compute step_1 = call_contract("MwValidateAmount", ctx)
  compute step_2 = call_contract("MwCheckFrozen", step_1)
  compute step_3 = call_contract("MwCheckBalance", step_2)

  output step_3 : PipelineContext
}
