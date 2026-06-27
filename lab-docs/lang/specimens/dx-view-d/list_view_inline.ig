module ListViewInline

-- Same as list_view_manual, but with the element library INLINED into one module — because
-- `call_contract` is module-local today (cross-module element reuse OOF'd: "unknown callee 'Leaf'
-- — not found in this module"). This version isolates whether the authoring SHAPE compiles at all.

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
  compute el = { tag: "leaf", attrs: attrs, text: text, intent: "", children: [] }
  output el : Element
}

contract Button {
  input attrs   : Attrs
  input text    : String
  input intent  : String
  compute el = { tag: "button", attrs: attrs, text: text, intent: intent, children: [] }
  output el : Element
}

-- The list screen view, hand-authored (feel the pain: a named compute per node, every Attrs spelled
-- out, and item rows written out one by one).
-- NOTE: this static/manual specimen intentionally avoids `map` for readability. The dynamic sibling
-- (`list_view_dynamic.ig`) proves map-based body construction — `map`/`fold`/`filter` DO exist.
contract ListView {
  input sel_title : String

  compute a_screen  = { dir: "row",  main: 0,   flex: 0, pad: 0,  gap: 0  }
  compute a_sidebar = { dir: "col",  main: 248, flex: 0, pad: 12, gap: 8  }
  compute a_detail  = { dir: "col",  main: 1,   flex: 1, pad: 18, gap: 14 }
  compute a_row     = { dir: "leaf", main: 40,  flex: 0, pad: 0,  gap: 0  }
  compute a_title   = { dir: "leaf", main: 30,  flex: 0, pad: 0,  gap: 0  }
  compute a_toggle  = { dir: "leaf", main: 48,  flex: 0, pad: 0,  gap: 0  }

  compute item0 = call_contract("Leaf",   a_row, "Review Ada's lead")
  compute item1 = call_contract("Leaf",   a_row, "Call Grace back")
  compute item2 = call_contract("Leaf",   a_row, "Send Linus the quote")
  compute add   = call_contract("Button", a_row, "+ add item", "add")

  compute sidebar_kids = [ item0, item1, item2, add ]
  compute sidebar = call_contract("Col", a_sidebar, sidebar_kids)

  compute d_title  = call_contract("Leaf",   a_title,  sel_title)
  compute d_toggle = call_contract("Button", a_toggle, "mark done", "toggle")
  compute detail_kids = [ d_title, d_toggle ]
  compute detail = call_contract("Col", a_detail, detail_kids)

  compute screen_kids = [ sidebar, detail ]
  compute screen = call_contract("Row", a_screen, screen_kids)

  output screen : Element
}
