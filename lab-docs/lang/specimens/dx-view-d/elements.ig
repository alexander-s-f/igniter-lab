module FrameElements

-- LAB-FRAME-DX-VIEW-D specimen — "elements as contracts" (Candidate D), authored ONLY on today's
-- live igniter surface, to feel exactly where the language pushes back. No sugar assumed here.

-- Shared attributes every element carries.
-- PAIN #1 (attr reuse): all fields are REQUIRED — no optional fields, no defaults, no record spread,
-- and `shape` inherits PORTS not DATA — so every single construction must spell out all five.
type Attrs {
  dir  : String   -- "col" | "row" | "leaf"
  main : Integer  -- fixed px, or flex weight
  flex : Integer  -- 1 = flex by weight, 0 = fixed size
  pad  : Integer
  gap  : Integer
}

-- A view node. RECURSIVE: `children` is a Collection of Element.
-- PROBE: does canon/lab typecheck a self-referential record type at all?
type Element {
  tag      : String
  attrs    : Attrs
  text     : String
  intent   : String
  children : Collection[Element]
}

-- The element library (this is the "elements.ig analogous to types.ig" idea) -------------------

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
