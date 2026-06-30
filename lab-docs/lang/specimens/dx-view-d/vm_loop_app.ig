module VmLoopApp

-- LAB-FRAME-VIEW-IG-VM-IN-THE-LOOP-P6 + LAB-FRAME-VIEW-EQ-WORKAROUND-REMOVAL-P7 — a fully
-- Igniter-authored view+logic app. State is an `.ig` record; the VIEW is `(State) -> Element` and the
-- REDUCER is `(State, key) -> State`, both run on igniter-vm. The host (frame-ui) only hit-tests a
-- click and threads JSON between the runs.
--
-- P7: selection is now authored with REAL equality. `LAB-VM-PRIMITIVE-EQ-PARITY-P1` proved the VM
-- executes `stdlib.primitive.eq` (`==` on String/Text/Integer/Bool), so the view marks each row
-- `selected = (row_key == state.sel)` directly — no host-side `n.id == sel` workaround and no
-- status-text echo stand-in. The bridge only RENDERS the authored `selected`; it never decides it.

type State { sel : String }

type Attrs {
  dir  : String
  main : Integer
  flex : Integer
  pad  : Integer
  gap  : Integer
}

-- Element carries `key` (the DOMAIN id a click carries back to the reducer) and the authored
-- `selected` flag the view computes by equality.
type Element {
  tag      : String
  attrs    : Attrs
  text     : String
  intent   : String
  key      : String
  selected : Bool
  children : Collection[Element]
}

contract Col {
  input attrs    : Attrs
  input children : Collection[Element]
  compute el = { tag: "col", attrs: attrs, text: "", intent: "", key: "", selected: false, children: children }
  output el : Element
}

contract Leaf {
  input attrs    : Attrs
  input text     : String
  input intent   : String
  input key      : String
  input selected : Bool
  compute el = { tag: "leaf", attrs: attrs, text: text, intent: intent, key: key, selected: selected, children: [] }
  output el : Element
}

-- VIEW: (State) -> Element. Three clickable leads; each row's selection is computed by REAL equality
-- over its stable domain key (`row_key == state.sel`).
contract View {
  input state : State

  compute a_side = { dir: "col",  main: 248, flex: 0, pad: 12, gap: 8 }
  compute a_row  = { dir: "leaf", main: 40,  flex: 0, pad: 0,  gap: 0 }

  compute sel0 = "lead:0" == state.sel
  compute sel1 = "lead:1" == state.sel
  compute sel2 = "lead:2" == state.sel

  compute n0 = call_contract("Leaf", a_row, "Review Ada's lead", "select", "lead:0", sel0)
  compute n1 = call_contract("Leaf", a_row, "Call Grace back", "select", "lead:1", sel1)
  compute n2 = call_contract("Leaf", a_row, "Send Linus the quote", "select", "lead:2", sel2)

  compute screen = call_contract("Col", a_side, [n0, n1, n2])
  output screen : Element
}

-- REDUCER: (State, key) -> State. Sets the selection to the clicked key. Pure, runs on igniter-vm.
contract Reduce {
  input state : State
  input key   : String
  compute next = { sel: key }
  output next : State
}
