-- LAB-IGNITER-WEB-RENDER-DECISION-P16 handlers (authored, pure; no DB).
-- RenderPage hands the request body (a ViewArtifact JSON string) through `Render`; igniter-web projects
-- it to escaped HTML via the P3 renderer and ships it as verbatim text/html bytes. `.ig` cannot author a
-- JSON literal (no string escapes), so the descriptor is sourced from `req.body`.
module RenderHandlers

import IgWebPrelude

pure contract RenderPage {
  input req : Request
  compute d : Decision = Render { status: 200, artifact_json: req.body }
  output d : Decision
}

-- Contrast: a plain data route still uses `Respond { body: String }` (JSON), unchanged by the render seam.
pure contract DataApi {
  input req : Request
  compute d : Decision = Respond { status: 200, body: "ok" }
  output d : Decision
}
