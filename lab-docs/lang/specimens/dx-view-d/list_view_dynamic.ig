module ListViewDynamic

-- (a') THE LIST SCREEN, DATA-BOUND & DYNAMIC, on today's live igniter — the realistic version.
-- The big surprise from the verify-first probes: `map`/`filter`/`fold`/`filter_map` EXIST in stdlib
-- with lambdas, so a DYNAMIC list IS expressible. A row per lead is `map(leads, l -> Leaf(...))`,
-- not a hand-unroll. (Elements must be inlined here because `call_contract` is module-local today.)

type Attrs {
  dir  : String
  main : Integer
  flex : Integer
  pad  : Integer
  gap  : Integer
}

type Element {
  tag      : String
  attrs    : Attrs
  text     : String
  intent   : String
  children : Collection[Element]
}

contract Col {
  input attrs    : Attrs
  input children : Collection[Element]
  compute el = { tag: "col", attrs: attrs, text: "", intent: "", children: children }
  output el : Element
}

contract Row {
  input attrs    : Attrs
  input children : Collection[Element]
  compute el = { tag: "row", attrs: attrs, text: "", intent: "", children: children }
  output el : Element
}

contract Leaf {
  input attrs : Attrs
  input text  : String
  compute el = { tag: "leaf", attrs: attrs, text: text, intent: "select", children: [] }
  output el : Element
}

contract Button {
  input attrs   : Attrs
  input text    : String
  input intent  : String
  compute el = { tag: "button", attrs: attrs, text: text, intent: intent, children: [] }
  output el : Element
}

-- The view: a row per lead (DYNAMIC, via map), an add button, and a detail column. Nesting is by
-- threading element outputs; repetition is a real `map` over the bound collection.
contract ListView {
  input lead_labels : Collection[String]   -- bound data (would be the leads' names)
  input sel_title   : String

  compute a_screen  = { dir: "row",  main: 0,   flex: 0, pad: 0,  gap: 0  }
  compute a_sidebar = { dir: "col",  main: 248, flex: 0, pad: 12, gap: 8  }
  compute a_detail  = { dir: "col",  main: 1,   flex: 1, pad: 18, gap: 14 }
  compute a_row     = { dir: "leaf", main: 40,  flex: 0, pad: 0,  gap: 0  }
  compute a_title   = { dir: "leaf", main: 30,  flex: 0, pad: 0,  gap: 0  }
  compute a_toggle  = { dir: "leaf", main: 48,  flex: 0, pad: 0,  gap: 0  }

  -- ONE map replaces the hand-unrolled rows: a Leaf per lead label.
  compute item_rows = map(lead_labels, label -> call_contract("Leaf", a_row, label))
  compute add       = call_contract("Button", a_row, "+ add item", "add")
  compute sidebar_kids = append(item_rows, add)
  compute sidebar = call_contract("Col", a_sidebar, sidebar_kids)

  compute d_title  = call_contract("Leaf",   a_title,  sel_title)
  compute d_toggle = call_contract("Button", a_toggle, "mark done", "toggle")
  compute detail   = call_contract("Col", a_detail, [ d_title, d_toggle ])

  compute screen = call_contract("Row", a_screen, [ sidebar, detail ])
  output screen : Element
}
