module ListViewManual
import FrameElements

-- (a) THE LIST SCREEN AUTHORED THE WAY YOU MUST WRITE IT TODAY.
-- Element-contracts compose fine — but feel the Axis-A pain: every node is a named `compute`,
-- every Attrs is spelled out in full, children are hand-built lists threading outputs, and the
-- item rows are written out one by one. NOTE: this manual specimen intentionally avoids `map` for
-- readability; `map`/`fold`/`filter` DO exist — the dynamic sibling (`list_view_dynamic.ig`) proves
-- map-based body construction.

contract ListViewManual {
  input sel_title : String   -- selected item's title (would come from state)

  -- PAIN #1 — attrs: required-only records, no defaults/spread/shape-data → spell every one out.
  compute a_screen  = { dir: "row",  main: 0,   flex: 0, pad: 0,  gap: 0  }
  compute a_sidebar = { dir: "col",  main: 248, flex: 0, pad: 12, gap: 8  }
  compute a_detail  = { dir: "col",  main: 1,   flex: 1, pad: 18, gap: 14 }
  compute a_row     = { dir: "leaf", main: 40,  flex: 0, pad: 0,  gap: 0  }
  compute a_title   = { dir: "leaf", main: 30,  flex: 0, pad: 0,  gap: 0  }
  compute a_toggle  = { dir: "leaf", main: 48,  flex: 0, pad: 0,  gap: 0  }

  -- PAIN #2 — nesting: one named compute per node; no inline child expressions.
  -- PAIN #3 — repeat: this manual specimen lists 3 rows by hand for readability. `map` DOES exist,
  --           so a dynamic list is `map(leads, l -> call_contract("Leaf", a_row, l))` — see
  --           `list_view_dynamic.ig`, which proves it. The pain here is the manual nesting, not map.
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
