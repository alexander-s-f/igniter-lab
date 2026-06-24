# Igniter Web File Export Thread v0

Date: 2026-06-20
Status: thread note / deferred wave seed
Authority: lab evidence only

Superseded status note (2026-06-24): the generic export/download wave remains deferred, but the blanket
"no raw response implementation" wording below is no longer current. `igniter-server` now has
`ResponseBody::Raw`, and `igniter-web` uses `Render` / `RenderView` to return verbatim `text/html` bytes.
What remains unimplemented is the app-facing generic file/download response shape with headers,
disposition, byte limits, storage handoff, and exporter projectors.

## Why This Exists

While shaping `LAB-IGNITER-RENDER-HTML-P3`, we hit the adjacent product case:

> Generate a report, for example Excel, and let the user download it.

This note preserves the thread so it does not get lost. It is not an
implementation card and does not change the current priority. First crystallize
HTML rendering; then launch the file/export wave.

## Core Decision

File download is not an Excel feature. It is a generic delivery primitive:

```text
structured descriptor -> host projector -> bytes -> generic response delivery
```

Examples:

- `ViewArtifact -> HTML bytes`
- `ReportDescriptor -> XLSX bytes`
- `TableDescriptor -> CSV bytes`
- `DocumentDescriptor -> PDF bytes`

The Igniter language should not generate binary files directly. Binary
serialization belongs to host/projector crates, outside `.ig` and outside
server-core domain knowledge.

## Layering

### 1. Projector Layer

Host crates turn structured descriptors into bytes:

```text
igniter-render-html:  ViewArtifact     -> html bytes
igniter-export-xlsx:  ReportDescriptor -> xlsx bytes
igniter-export-csv:   TableDescriptor  -> csv bytes
```

These crates may use format-specific Rust libraries. Those dependencies must not
enter the Igniter language or `igniter-server` core.

### 2. Response Delivery Layer

Server-core eventually needs a generic raw/binary response seam:

```text
bytes + content_type + headers + disposition
```

For downloads, `Content-Disposition: attachment; filename="report.xlsx"` is the
standard mechanism. `ServerResponse.headers` are already written to the wire;
the missing part is raw/verbatim body support and app-level access to response
headers/body shape.

### 3. Storage / Effect Layer for Large Files

Large or slow exports should not run as ordinary request rendering.

Preferred shape:

```text
InvokeEffect("export-report", params)
  -> host capability generates artifact
  -> stores bytes in object/file storage
  -> receipt records artifact id/location
  -> client downloads later by artifact id or signed URL
```

This reuses the existing capability-IO / receipt / idempotency model instead of
making the web request path responsible for long-running binary generation.

## Sync vs Async

### Small / Synchronous

Use inline response:

```text
ReportDescriptor -> xlsx bytes -> RawResponse
```

Bounded v0 constraints:

- whole body buffered in memory;
- explicit max byte limit;
- fixed `Content-Length`;
- no streaming/chunked response yet.

### Large / Asynchronous

Use effect + storage:

```text
request -> export effect -> receipt/artifact_id -> later download
```

At scale, prefer redirecting to a signed object-storage URL over proxying large
bytes through `igniter-server`.

## Security / Boundary Notes

Do not give apps a generic `send_file(path)` primitive.

Reasons:

- path traversal risk;
- unclear file ownership/lifetime;
- local filesystem leakage;
- authorization and cleanup become implicit;
- server-core would learn too much about app storage.

Safer alternatives:

- small inline bytes produced by a bounded host projector;
- large files stored behind a storage capability and addressed by artifact id;
- signed URL handoff for object storage.

## Proposed Future Sequence

Keep the current HTML path first:

1. `LAB-IGNITER-RENDER-HTML-P3`
   - prove `ViewArtifact JSON -> escaped deterministic HTML`.
   - no server/raw-response changes.

Then open the export wave:

2. `LAB-IGNITER-WEB-RAW-RESPONSE-READINESS-P4`
   - generic bytes response, content type, headers, disposition, size limit.
   - no streaming yet.

3. `LAB-IGNITER-WEB-FILE-EXPORT-READINESS-P5`
   - descriptor-to-bytes family: xlsx/csv/pdf/html.
   - sync inline vs async effect+storage.
   - artifact id, signed URL, retention, idempotency.

4. `LAB-IGNITER-EXPORT-XLSX-P6`
   - proof crate: `ReportDescriptor -> .xlsx bytes`.
   - no server-core dependency.

## Non-Goals for This Thread Note

- No `.ig.html`.
- No Excel implementation.
- No generic file/download response implementation (the later raw-byte/HTML response seam exists; this
  thread still does not implement headers/disposition/storage/export projectors).
- No streaming.
- No file storage implementation.
- No server-core domain knowledge.
- No canon claim.

## Current Recommendation

Treat `RAW-RESPONSE` as the common seam, not as an HTML-specific feature. HTML,
XLSX, CSV, and PDF should all use the same generic delivery primitive after
their respective host projector has produced bytes.
