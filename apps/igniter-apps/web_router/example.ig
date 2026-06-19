module WebRouterExample
import WebRouterTypes
import WebRouterServe

-- ============================================================
-- Example: serve a handful of requests through the router
-- ============================================================

pure contract MakeReq {
  input method : String
  input path : String
  compute r = { method: method, path: path }
  output r : HttpRequest
}

-- GET /  → 200 "home"
contract RunHome {
  compute req = call_contract("MakeReq", "GET", "/")
  compute resp = call_contract("Serve", req)
  output resp : HttpResponse
}

-- GET /articles/42  → 200 "article"
contract RunArticle {
  compute req = call_contract("MakeReq", "GET", "/articles/42")
  compute resp = call_contract("Serve", req)
  output resp : HttpResponse
}

-- POST /articles  → 201 "article created"
contract RunCreate {
  compute req = call_contract("MakeReq", "POST", "/articles")
  compute resp = call_contract("Serve", req)
  output resp : HttpResponse
}

-- GET /nope  → 404
contract RunMissing {
  compute req = call_contract("MakeReq", "GET", "/nope")
  compute resp = call_contract("Serve", req)
  output resp : HttpResponse
}

entrypoint RunArticle
