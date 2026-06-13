module SimConstraints
import SimTypes
import stdlib.collection.{ map, filter }

-- ============================================================
-- Constraint[T] Validation Engine
-- ============================================================
-- Demonstrates: Constraint[T], Decision[T]

-- ── Validate a single entity against a constraint ───────────

contract CheckConstraint {
  input e : Entity
  input c : ConstraintDef

  compute field_val = if c.field == "population" {
    e.population.current
  } else {
    if c.field == "resources" {
      e.resources.current
    } else {
      e.health
    }
  }

  compute is_valid = if field_val < c.min_val {
    false
  } else {
    if field_val > c.max_val { false } else { true }
  }

  compute violation = if is_valid {
    call_contract("MakeViolation", "NONE", 0, "", 0, "OK")
  } else {
    call_contract("MakeViolation", c.name, e.id, c.field, field_val, concat(concat(c.name, " violated for entity "), e.name))
  }

  output violation : ConstraintViolation
}

contract MakeViolation {
  input constraint_name : String
  input entity_id : Integer
  input field : String
  input actual_val : Integer
  input message : String

  compute v = {
    constraint_name: constraint_name,
    entity_id: entity_id,
    field: field,
    actual_val: actual_val,
    message: message
  }

  output v : ConstraintViolation
}

-- ── Decision Engine: What action to take on violation ───────
-- Demonstrates Decision[T] as a first-class branching concept

contract DecideAction {
  input violation : ConstraintViolation
  input config : SimConfig

  -- Decision Tree:
  -- If population < min => "EMERGENCY_BOOST"
  -- If population > max => "CULL"
  -- If resources < min => "IMPORT"
  -- If resources > max => "EXPORT"
  compute action = if violation.field == "population" {
    if violation.actual_val < config.min_population {
      "EMERGENCY_BOOST"
    } else {
      "CULL"
    }
  } else {
    if violation.field == "resources" {
      if violation.actual_val < config.min_resources {
        "IMPORT"
      } else {
        "EXPORT"
      }
    } else {
      "WARN"
    }
  }

  compute corrective_event = {
    tick: 0,
    event_type: action,
    source_id: violation.entity_id,
    target_id: violation.entity_id,
    amount: if violation.actual_val < config.min_population {
      config.min_population - violation.actual_val
    } else {
      if violation.actual_val > config.max_population {
        violation.actual_val - config.max_population
      } else { 0 }
    },
    rule_name: concat("AutoCorrect:", violation.constraint_name)
  }

  output action : String
  output corrective_event : SimEvent
}
