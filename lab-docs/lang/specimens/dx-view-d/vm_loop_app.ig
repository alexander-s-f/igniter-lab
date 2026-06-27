module VmLoopApp

-- LAB-FRAME-VIEW-IG-VM-IN-THE-LOOP-P6 — a fully Igniter-authored view+logic app.
-- State is an `.ig` record; the VIEW is `(State) -> Element` and the REDUCER is `(State, key) -> State`,
-- both run on igniter-vm. The host (frame-ui) only hit-tests a click and threads JSON between the runs.
--
-- NOTE (VM parity gap, routed to VM owners): igniter-vm does NOT implement `stdlib.primitive.eq`
-- (`==` on Integer or String) even though the compiler accepts it and `<` works. So this app avoids
-- equality: the re-projected view reflects new state by echoing `state.sel` into a status leaf's TEXT
-- (a state-dependent render that needs no `==`), and the reducer assigns `sel = key` (action routing
-- is the host's job). Once `eq` lands, the view can mark the selected row directly.

type State { sel : String }

type Attrs {
  dir  : String
  main : Integer
  flex : Integer
  pad  : Integer
  gap  : Integer
}

-- Element carries `key` (the DOMAIN id a click carries back to the reducer).
type Element {
  tag      : String
  attrs    : Attrs
  text     : String
  intent   : String
  key      : String
  children : Collection[Element]
}

contract Col {
  input attrs    : Attrs
  input children : Collection[Element]
  compute el = { tag: "col", attrs: attrs, text: "", intent: "", key: "", children: children }
  output el : Element
}

contract Leaf {
  input attrs  : Attrs
  input text   : String
  input intent : String
  input key    : String
  compute el = { tag: "leaf", attrs: attrs, text: text, intent: intent, key: key, children: [] }
  output el : Element
}

-- VIEW: (State) -> Element. Three clickable leads + a status leaf echoing the current selection.
contract View {
  input state : State

  compute a_side   = { dir: "col",  main: 248, flex: 0, pad: 12, gap: 8 }
  compute a_row    = { dir: "leaf", main: 40,  flex: 0, pad: 0,  gap: 0 }
  compute a_status = { dir: "leaf", main: 24,  flex: 0, pad: 0,  gap: 0 }

  compute n0 = call_contract("Leaf", a_row, "Review Ada's lead", "select", "lead:0")
  compute n1 = call_contract("Leaf", a_row, "Call Grace back", "select", "lead:1")
  compute n2 = call_contract("Leaf", a_row, "Send Linus the quote", "select", "lead:2")
  compute status = call_contract("Leaf", a_status, state.sel, "", "status")

  compute screen = call_contract("Col", a_side, [n0, n1, n2, status])
  output screen : Element
}

-- REDUCER: (State, key) -> State. Sets the selection to the clicked key. Pure, runs on igniter-vm.
contract Reduce {
  input state : State
  input key   : String
  compute next = { sel: key }
  output next : State
}
