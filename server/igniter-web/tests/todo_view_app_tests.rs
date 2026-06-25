// igniter-web/tests/todo_view_app_tests.rs — LAB-TODOAPP-VIEW-MANIFEST-P2
// Proves the JSON-first TodoApp view path end-to-end: authored `.igweb` view routes + `.ig` handlers
// build a typed `View` descriptor returned via `RespondView`, and the loopback response body root IS
// that clean view JSON object — NOT a `{"body": "<escaped-json>"}` double-wrap. Fake data, no DB, no Rust.

use igniter_server::protocol::ServerApp;
use igniter_web::runner::check_app_dir;
use igniter_web::testkit::{roundtrip, roundtrip_raw};
use igniter_web::{build_igweb_app, IgWebBuildInput};
use serde_json::json;
use std::path::PathBuf;
use std::sync::Arc;

// LAB-TODOAPP-VIEW-HTML-P17: a Todo-shaped full ViewArtifact form. The first item text carries
// `<script>` to prove escaping on the way to HTML bytes. Built in Rust; sent as the request body.
const TODO_ARTIFACT: &str = r#"{"artifact":"view","layout":"form","title":"Todos","body":[{"kind":"label","text":"Buy milk <script>"},{"kind":"label","text":"Write the spec"},{"kind":"button","id":"done","label":"Done","action":"submit"}]}"#;

fn dir() -> PathBuf {
    PathBuf::from(format!(
        "{}/examples/todo_view_app",
        env!("CARGO_MANIFEST_DIR")
    ))
}

fn sources() -> Vec<PathBuf> {
    ["todo_views.ig", "routes.igweb"]
        .iter()
        .map(|f| dir().join(f))
        .collect()
}

fn build() -> Arc<dyn ServerApp + Send + Sync> {
    build_igweb_app(IgWebBuildInput {
        sources: sources(),
        entry: "Serve".into(),
    })
    .expect("build todo_view_app from authored files")
}

#[test]
fn builds_from_manifest_with_no_authored_rust() {
    // The runner builds the app from igweb.toml alone (no per-app Rust) — same path `igweb-serve` uses.
    let report = check_app_dir(&dir()).expect("check_app_dir must build the view app");
    assert_eq!(report.entry, "Serve");
}

#[test]
fn index_view_body_root_is_the_clean_view_object() {
    let app = build();
    let (status, body) = roundtrip(&*app, "GET", "/", &[], "");
    assert_eq!(status, 200);

    // The body ROOT is the View descriptor — recognizable structured fields, nested items array.
    assert_eq!(body["kind"], json!("todo_index"));
    assert_eq!(body["title"], json!("Todos"));
    assert_eq!(body["items"][0]["key"], json!("1"));
    assert_eq!(body["items"][0]["label"], json!("Buy milk"));
    assert_eq!(body["items"][1]["key"], json!("2"));
    assert_eq!(body["items"][1]["label"], json!("Write the spec"));

    // NOT double-wrapped (`{"body": "..."}`) and NOT a stringified JSON document.
    assert!(
        body.get("body").is_none(),
        "must not be {{\"body\": ...}}: {body}"
    );
    assert!(
        body.is_object(),
        "root must be a JSON object, not a string: {body}"
    );
    // Plain records serialize clean — no VM variant discriminants leak into the view root.
    assert!(body.get("__arm").is_none(), "no __arm in view root: {body}");
    assert!(
        body.get("__variant").is_none(),
        "no __variant in view root: {body}"
    );
}

#[test]
fn detail_view_uses_path_param() {
    let app = build();
    let (status, body) = roundtrip(&*app, "GET", "/todos/42", &[], "");
    assert_eq!(status, 200);
    assert_eq!(body["kind"], json!("todo_detail"));
    assert_eq!(body["items"][0]["key"], json!("42")); // captured todo_id reached the view
}

#[test]
fn alias_route_serves_same_index_view() {
    let app = build();
    let (status, body) = roundtrip(&*app, "GET", "/todos", &[], "");
    assert_eq!(status, 200);
    assert_eq!(body["kind"], json!("todo_index"));
}

#[test]
fn api_data_route_keeps_old_respond_shape() {
    // Contrast: a plain `Respond { body: String }` route still wraps as `{"body": ...}` — the view
    // seam is additive, it does not change the existing data-response shape.
    let app = build();
    let (status, body) = roundtrip(&*app, "GET", "/api/health", &[], "");
    assert_eq!(status, 200);
    assert_eq!(body["body"], json!("ok"));
}

#[test]
fn unknown_and_method_refusals_unchanged() {
    let app = build();
    assert_eq!(roundtrip(&*app, "GET", "/missing", &[], "").0, 404);
    assert_eq!(roundtrip(&*app, "POST", "/", &[], "").0, 405);
}

/// Split a raw HTTP/1.1 response into (lower-cased head, body).
fn split(wire: &str) -> (String, &str) {
    let pos = wire.find("\r\n\r\n").map(|i| i + 4).unwrap_or(wire.len());
    (wire[..pos].to_lowercase(), &wire[pos..])
}

#[test]
fn todo_html_preview_returns_verbatim_text_html() {
    // P17: the SAME Todo app gains one HTML route via the P16 `Render` seam; the JSON routes are untouched.
    let app = build();
    let (status, wire) = roundtrip_raw(&*app, "POST", "/todos/html-preview", &[], TODO_ARTIFACT);
    assert_eq!(status, 200);
    let (head, body) = split(&wire);

    assert!(
        head.contains("content-type: text/html; charset=utf-8"),
        "head: {head}"
    );
    assert!(!head.contains("application/json"));
    // verbatim HTML document — not JSON-quoted, not `{"body": ...}` wrapped.
    assert!(body.starts_with("<!DOCTYPE html>"), "body: {body}");
    assert!(!body.contains("{\"body\""));
    // Todo content from the supplied ViewArtifact is present, ESCAPED.
    assert!(body.contains("<title>Todos</title>"));
    assert!(body.contains("Buy milk &lt;script&gt;"));
    assert!(body.contains("Write the spec"));
    assert!(body.contains("data-action=\"submit\""));
    // the malicious `<script>` never becomes a real script tag.
    assert!(
        !body.contains("<script>"),
        "raw <script> must not appear: {body}"
    );
}

#[test]
fn todo_html_preview_invalid_artifact_is_json_500() {
    let app = build();
    // valid JSON but not a view artifact → renderer rejects → JSON 500, not HTML, not a panic.
    let (status, wire) =
        roundtrip_raw(&*app, "POST", "/todos/html-preview", &[], r#"{"todo":"x"}"#);
    assert_eq!(status, 500);
    let (head, body) = split(&wire);
    assert!(
        head.contains("content-type: application/json"),
        "head: {head}"
    );
    assert!(!body.starts_with("<!DOCTYPE"), "must not be HTML");
    assert!(body.contains("render failed"));
}

// ---- LAB-IGNITER-WEB-VIEWARTIFACT-AUTHORING-P19: HTML authored from typed `.ig` records (RenderView) ----

#[test]
fn authored_renderview_returns_html_built_from_ig_records() {
    let app = build();
    // No request body — the ViewArtifact is authored in `.ig` records; the path param flows in.
    let (status, wire) = roundtrip_raw(&*app, "GET", "/todos/authored-html/42", &[], "");
    assert_eq!(status, 200);
    let (head, body) = split(&wire);

    assert!(
        head.contains("content-type: text/html; charset=utf-8"),
        "head: {head}"
    );
    assert!(!head.contains("application/json"));
    assert!(body.starts_with("<!DOCTYPE html>"), "body: {body}");
    assert!(!body.contains("{\"body\""));
    assert!(body.contains("<title>Todo Detail</title>"));
    // route param flowed into a leaf field.
    assert!(
        body.contains("<p class=\"ig-label\">42</p>"),
        "param in artifact: {body}"
    );
    // the typed `button` record rendered.
    assert!(body.contains("data-action=\"submit\""));
    // a `<script>` leaf is escaped on the way to bytes.
    assert!(body.contains("Buy milk &lt;script&gt;"));
    assert!(
        !body.contains("<script>"),
        "raw <script> must not appear: {body}"
    );
}

#[test]
fn helper_authored_html_is_byte_identical_to_direct_records() {
    // P20: the helper-contract route and the P19 direct-record route build the SAME artifact from the same
    // inputs → their rendered HTML must be byte-identical (helpers are sugar over the proven record model).
    let app = build();
    let (s_helper, w_helper) = roundtrip_raw(&*app, "GET", "/todos/helper-html/7", &[], "");
    let (s_direct, w_direct) = roundtrip_raw(&*app, "GET", "/todos/authored-html/7", &[], "");
    assert_eq!(s_helper, 200);
    assert_eq!(s_direct, 200);
    let (h_helper, b_helper) = split(&w_helper);
    let (_, b_direct) = split(&w_direct);

    assert!(h_helper.contains("content-type: text/html; charset=utf-8"));
    assert_eq!(
        b_helper, b_direct,
        "helper-authored HTML must equal direct-record HTML"
    );
    // sanity on the helper output itself: param flowed through a helper; `<script>` escaped.
    assert!(b_helper.contains("<title>Todo Detail</title>"));
    assert!(b_helper.contains("<p class=\"ig-label\">7</p>"));
    assert!(b_helper.contains("Buy milk &lt;script&gt;"));
    assert!(b_helper.contains("data-action=\"submit\""));
    assert!(!b_helper.contains("<script>"));
}

#[test]
fn list_html_maps_domain_collection_to_nodes() {
    // P21: `body : Collection[HtmlNode] = map(todos, t -> call_contract("TodoLabel", t))` — a domain
    // collection transformed into nodes, NOT manual per-node enumeration.
    let app = build();
    let (status, wire) = roundtrip_raw(&*app, "GET", "/todos/list-html", &[], "");
    assert_eq!(status, 200);
    let (head, body) = split(&wire);

    assert!(
        head.contains("content-type: text/html; charset=utf-8"),
        "head: {head}"
    );
    assert!(body.starts_with("<!DOCTYPE html>"), "body: {body}");
    assert!(body.contains("<title>Todos</title>"));
    // both items render, in authored order (map preserves order).
    let i_milk = body.find("Buy milk").expect("first item present");
    let i_spec = body.find("Write the spec").expect("second item present");
    assert!(i_milk < i_spec, "deterministic authored order");
    // malicious title text is escaped on the way to bytes.
    assert!(body.contains("Buy milk &lt;script&gt;"));
    assert!(
        !body.contains("<script>"),
        "raw <script> must not appear: {body}"
    );
}

#[test]
fn pending_html_filters_then_maps_domain_collection() {
    // P22: `filter(todos, t -> t.done == false)` then `map` — a conditional list. Only pending (done:false)
    // items render, in original order; the done item is omitted.
    let app = build();
    let (status, wire) = roundtrip_raw(&*app, "GET", "/todos/pending-html", &[], "");
    assert_eq!(status, 200);
    let (head, body) = split(&wire);

    assert!(
        head.contains("content-type: text/html; charset=utf-8"),
        "head: {head}"
    );
    assert!(body.starts_with("<!DOCTYPE html>"), "body: {body}");
    assert!(body.contains("<title>Pending</title>"));
    // kept: the two pending items, in original order.
    let i_milk = body.find("Buy milk").expect("pending item 1 present");
    let i_bills = body.find("Pay bills").expect("pending item 3 present");
    assert!(i_milk < i_bills, "kept items in original order");
    // omitted: the done item.
    assert!(
        !body.contains("Write the spec"),
        "done item must be omitted: {body}"
    );
    // kept malicious text is still escaped.
    assert!(body.contains("Buy milk &lt;script&gt;"));
    assert!(
        !body.contains("<script>"),
        "raw <script> must not appear: {body}"
    );
}

#[test]
fn filter_html_renders_select_options_in_order_escaped() {
    // P23: a `select` node authored from a `Collection[String]` via MakeSelect — options render in
    // authored order, each escaped.
    let app = build();
    let (status, wire) = roundtrip_raw(&*app, "GET", "/todos/filter-html", &[], "");
    assert_eq!(status, 200);
    let (head, body) = split(&wire);

    assert!(
        head.contains("content-type: text/html; charset=utf-8"),
        "head: {head}"
    );
    assert!(body.starts_with("<!DOCTYPE html>"), "body: {body}");
    assert!(
        body.contains("<select name=\"status\">"),
        "select rendered: {body}"
    );
    // options in authored order.
    let i_all = body
        .find("<option value=\"all\">all</option>")
        .expect("option all");
    let i_pending = body
        .find("pending &lt;script&gt;")
        .expect("option pending escaped");
    let i_done = body
        .find("<option value=\"done\">done</option>")
        .expect("option done");
    assert!(
        i_all < i_pending && i_pending < i_done,
        "options in authored order"
    );
    // malicious option text escaped; no raw script.
    assert!(
        !body.contains("<script>"),
        "raw <script> must not appear: {body}"
    );
    // the sibling button still renders (mixed node kinds in one body).
    assert!(body.contains("data-action=\"/todos\""));
}

#[test]
fn authored_renderview_unsupported_node_fails_closed_to_json_500() {
    let app = build();
    let (status, wire) = roundtrip_raw(&*app, "GET", "/bad-node", &[], "");
    assert_eq!(status, 500, "unsupported `kind` → 500, not a panic");
    let (head, body) = split(&wire);
    assert!(
        head.contains("content-type: application/json"),
        "head: {head}"
    );
    assert!(!body.starts_with("<!DOCTYPE"), "must not be HTML");
    assert!(body.contains("render failed"));
    assert!(body.contains("unsupported_node"), "kind surfaced: {body}");
}

// ---- LAB-IGNITER-WEB-VIEWARTIFACT-LINK-NODE: an authored `link` node, path param → safe relative href ----

#[test]
fn link_node_renders_safe_relative_href_from_path_param() {
    // No request body — `MakeLink` + `FormView` author the artifact in `.ig` records; the route param
    // `:todo_id` flows into BOTH the visible label and a fail-closed relative href, rendered via RenderView.
    let app = build();
    let (status, wire) = roundtrip_raw(&*app, "GET", "/todos/link-html/42", &[], "");
    assert_eq!(status, 200);
    let (head, body) = split(&wire);
    assert!(
        head.contains("content-type: text/html; charset=utf-8"),
        "head: {head}"
    );
    assert!(body.starts_with("<!DOCTYPE html>"), "body: {body}");
    assert!(body.contains("<title>Navigation</title>"));
    // the path param flowed into both the href and the label; rendered as a safe <a>.
    assert!(
        body.contains("<a class=\"ig-link\" href=\"/todos/42\">Todo 42</a>"),
        "link with param in href + text: {body}"
    );
}

// ---- LAB-IGNITER-WEB-VIEWARTIFACT-LINK-NAV-P27: detail links + next-page link as a flat HtmlNode list ----

#[test]
fn nav_html_renders_detail_links_and_next_page_link() {
    // A realistic nav view: map a domain collection to per-row detail links, then `append` a next-page
    // cursor link — all flat `link` nodes + app-local helpers, no schema/layout change.
    let app = build();
    let (status, wire) = roundtrip_raw(&*app, "GET", "/todos/nav-html", &[], "");
    assert_eq!(status, 200);
    let (head, body) = split(&wire);
    assert!(
        head.contains("content-type: text/html; charset=utf-8"),
        "head: {head}"
    );
    assert!(body.starts_with("<!DOCTYPE html>"), "body: {body}");

    // two detail links with safe relative hrefs, label = todo title, in authored order.
    let i_d1 = body
        .find("<a class=\"ig-link\" href=\"/todos/1\">")
        .expect("detail link 1");
    let i_d2 = body
        .find("<a class=\"ig-link\" href=\"/todos/2\">Write the spec</a>")
        .expect("detail link 2");
    assert!(i_d1 < i_d2, "detail links in authored order");

    // one next-page (cursor) link with a safe relative href, appended after the detail links.
    let i_next = body
        .find("<a class=\"ig-link\" href=\"/todos?after=todo_2\">Next page</a>")
        .expect("next-page link");
    assert!(i_d2 < i_next, "next-page link appended last");

    // the malicious title is escaped on the way through the link path; no raw script.
    assert!(
        body.contains("href=\"/todos/1\">Buy milk &lt;script&gt;</a>"),
        "detail link label escaped: {body}"
    );
    assert!(
        !body.contains("<script>"),
        "raw <script> must not appear: {body}"
    );
}
