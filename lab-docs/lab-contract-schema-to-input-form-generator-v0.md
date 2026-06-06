# Contract Schema-to-Input Form Generator (v0)

Status: `experimental · lab-only · implementation`
Track: `lab-contract-schema-to-input-form-generator-v0`
Base: `lab-igniter-lang-to-gui-research-boundary-v0.md`

---

## 1. Context & Architecture

This document implements the contract schema-to-form generator prototype inside `igniter-ide`. The generator reads compiled contract JSON artifacts from the compiler output directory, adapts their input signatures to a type-safe form, validates user values, and compiles a copyable JSON input packet.

### 1.1 Structural Distinctions

To ensure complete separation of concerns, we distinguish between three graphical layers:

| Layer | Input Source | Primary Purpose | Execution State |
| :--- | :--- | :--- | :--- |
| **Form Generator** | Compiled contract `input_ports` / `type_signature` schema | Validating and compiling inputs for a contract | Pre-execution (statically validated, non-executing) |
| **View DSL (VDSL)** | Custom HTML layout tree (`view_tree.json`) | Styled, structured component/tag presentation | Passive layout rendering |
| **State Slots** | `state_slots` bindings + Runtime Result packet | Reactive interpolation of computed values | Post-execution (VM trace mapping) |

---

## 2. Compiled Contract Schema Survey

We surveyed actual compiler JSON outputs (`loops_and_recursion.igapp/contracts/loop_tester.json`, `decimal_contract.igapp/contracts/bid_summary.json`, and `add.igapp/contracts/add.json`) to confirm field names and structural layout.

### 2.1 JSON Schema Pattern

Compiler-generated JSON contracts represent inputs using the `input_ports` array and fallback to `type_signature.inputs`:

```json
{
  "contract_id": "BidSummary",
  "input_ports": [
    {
      "lifecycle": "local",
      "name": "base_bid",
      "required": true,
      "type_tag": "Decimal[2]"
    },
    {
      "lifecycle": "local",
      "name": "tax_rate",
      "required": true,
      "type_tag": "Decimal[4]"
    }
  ],
  "type_signature": {
    "inputs": {
      "base_bid": "Decimal[2]",
      "tax_rate": "Decimal[4]"
    }
  }
}
```

---

## 3. Implementation Details

### 3.1 Schema Adapter

The Svelte 5 component uses a schema adapter `getPorts(contractData)` that maps these inputs to a common `InputPort` structure:
```typescript
interface InputPort {
  name: string
  required: boolean
  type_tag: string
}
```
If `input_ports` is missing, the adapter extracts ports from `type_signature.inputs` and marks all inputs as required by default.

### 3.2 Form Mapping & Validation Rules

Form controls and validations map dynamically to compiler types:

-   **`String`** -> Rendered as `<input type="text" />`. Validates required bounds.
-   **`Integer`** -> Rendered as `<input type="number" step="1" />`. Client-side validation uses `/^-?\d+$/` to reject any floating-point or decimal characters.
-   **`Decimal` / `Decimal[X]` / `Float`** -> Rendered as `<input type="number" step="any" />`. Validates against `/^-?\d+(\.\d+)?$/` to verify valid numeric bounds.
-   **`Boolean`** -> Rendered as checkbox toggle. Checked state maps directly to boolean value.
-   **`Array[T]` / `Collection[T]`** -> Rendered as a dynamic tabular row editor. Developers can click `+ Add Row` to add empty string entries and `✕` to remove specific rows. Each row is validated individually against type `T` (e.g., each item in `Array[Integer]` must match integer criteria).
-   **Unsupported / Unknown types** -> Rendered as high-visibility warning box blocking serialization. The port name is appended to the `unsupported_fields` list.

---

## 4. JSON Packet Schema

The generator produces a JSON packet of format:

```typescript
export interface InputPacket {
  contract_name: string
  input_values: Record<string, any>
  validation_status: 'valid' | 'invalid'
  unsupported_fields: string[]
  authority_marker: 'lab_only_non_execution'
  generated_at: string // ISO timestamp
}
```

---

## 5. Risk & Security Analysis

1.  **Strict Non-Execution Boundary**:
    -   The generator operates entirely client-side inside the Tauri Svelte canvas.
    -   No VM invocation or runtime dispatch command is triggered.
    -   The copyable JSON packet is marked with `authority_marker: "lab_only_non_execution"`.
2.  **Robust Type Escape**:
    -   Unknown or complex user-defined types (e.g. custom struct parameters) render as disabled field panels. They cannot be serialized and force `validation_status` to `"invalid"`, preventing malformed executions.

---

## 6. Proof Matrix Verification

| Rule ID | Requirement | Result | Verification Notes |
| :--- | :--- | :--- | :--- |
| **GUIF-1** | Compiled contract JSON shape surveyed | `PASS` | Documented in Section 2. Mapped `input_ports` and `type_signature`. |
| **GUIF-2** | Schema adapter handles at least two real contracts | `PASS` | Adapter successfully parses and adapts both `BidSummary` (decimals) and `LoopTester` (arrays/integers). |
| **GUIF-3** | String input renders and validates | `PASS` | Text fields validate empty states and map to strings. |
| **GUIF-4** | Integer input renders and rejects non-integers | `PASS` | Number input with regex `/^-?\d+$/` rejects decimal points or text. |
| **GUIF-5** | Boolean input renders and serializes | `PASS` | Renders toggle checkbox and maps to `true`/`false`. |
| **GUIF-6** | Decimal/Float or unsupported numeric handled explicitly | `PASS` | `Decimal[X]` and `Float` parse as floating-point decimals. |
| **GUIF-7** | Array/Collection has row editor or fails closed | `PASS` | Implemented dynamic row editor with element-level validation. |
| **GUIF-8** | Unsupported types do not silently serialize | `PASS` | Listed in `unsupported_fields` and flags packet as `"invalid"`. |
| **GUIF-9** | Output packet is valid JSON and marked `lab_only_non_execution` | `PASS` | Serializes to standard JSON carrying the exact non-execution marker. |
| **GUIF-10**| No VM/runtime execution path exists | `PASS` | Operating completely static in client-side; dispatch code omitted. |
| **GUIF-11**| `npm run build` passes | `PASS` | Vite static build completed successfully. |
| **GUIF-12**| `npm run check` result is recorded | `PASS` | Verified that typecheck errors are confined to pre-existing errors in `DebuggerPanel.svelte`. |
| **GUIF-13**| `igniter-lang/**` remains untouched | `PASS` | No files inside canonical `igniter-lang` were modified. |
| **GUIF-14**| No stable/public/production/runtime claims | `PASS` | Kept as lab-only sandbox tool. |
