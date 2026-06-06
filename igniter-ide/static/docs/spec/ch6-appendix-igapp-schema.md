# Appendix: .igapp Package JSON Schemas

This appendix defines the normative JSON Schema specifications for the `.igapp/` application package format.

These schemas serve as the conformance criteria for standard compliance verification of alternative compilers and virtual machines. Any compliant compiler MUST produce files matching these schemas, and any compliant virtual machine MUST successfully validate input files against them before load time.

---

## 1. Application Manifest (`manifest.json`)

The manifest file defines the entry points, compilation hashes, contract fragment classifications, and metadata indices for the application bundle.

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "IgniterApplicationManifest",
  "type": "object",
  "required": [
    "kind",
    "format",
    "format_version",
    "grammar_version",
    "language_version",
    "program_id",
    "source_hash",
    "source_path",
    "artifact_hash",
    "compilation_report_ref",
    "semantic_ir_ref",
    "fragment_class",
    "contracts",
    "contract_index",
    "contract_refs"
  ],
  "properties": {
    "kind": {
      "type": "string",
      "const": "igapp_manifest"
    },
    "format": {
      "type": "string",
      "enum": ["igapp_dir", "igapp_archive"]
    },
    "format_version": {
      "type": "string"
    },
    "grammar_version": {
      "type": "string"
    },
    "language_version": {
      "type": "string"
    },
    "program_id": {
      "type": "string",
      "pattern": "^semanticir/[a-f0-9]{16}$"
    },
    "source_hash": {
      "type": "string",
      "pattern": "^sha256:[a-f0-9]{64}$"
    },
    "source_path": {
      "type": "string"
    },
    "artifact_hash": {
      "type": "string",
      "pattern": "^sha256:[a-f0-9]{64}$"
    },
    "compilation_report_ref": {
      "type": "string",
      "pattern": "^compilation_report/[a-f0-9]{16}$"
    },
    "semantic_ir_ref": {
      "type": "string",
      "pattern": "^semanticir/[a-f0-9]{16}$"
    },
    "fragment_class": {
      "type": "string",
      "enum": ["core", "stream", "temporal", "escape", "mixed"]
    },
    "contracts": {
      "type": "array",
      "items": {
        "type": "string"
      }
    },
    "contract_refs": {
      "type": "object",
      "additionalProperties": {
        "type": "string",
        "pattern": "^contract/[A-Za-z0-9_]+/sha256:[a-f0-9]{24}$"
      }
    },
    "contract_index": {
      "type": "object",
      "additionalProperties": {
        "type": "object",
        "required": ["contract_path", "contract_ref", "fragment_class"],
        "properties": {
          "contract_path": {
            "type": "string"
          },
          "contract_ref": {
            "type": "string",
            "pattern": "^contract/[A-Za-z0-9_]+/sha256:[a-f0-9]{24}$"
          },
          "fragment_class": {
            "type": "string",
            "enum": ["core", "stream", "temporal", "escape"]
          },
          "temporal": {
            "type": "object",
            "required": ["axes", "required_capabilities", "coordinates"],
            "properties": {
              "axes": {
                "type": "array",
                "items": { "type": "string", "enum": ["valid_time", "transaction_time"] }
              },
              "required_capabilities": {
                "type": "array",
                "items": { "type": "string" }
              },
              "coordinates": {
                "type": "array",
                "items": {
                  "type": "object",
                  "required": ["name", "axis", "source_ref", "type"],
                  "properties": {
                    "name": { "type": "string" },
                    "axis": { "type": "string", "enum": ["valid_time", "transaction_time"] },
                    "source_ref": { "type": "string" },
                    "type": { "type": "string" }
                  }
                }
              },
              "cache_key_schema_hint": {
                "type": "object",
                "required": ["schema", "fragment", "axis", "coordinate_names"],
                "properties": {
                  "schema": { "type": "string" },
                  "fragment": { "type": "string", "enum": ["TEMPORAL"] },
                  "axis": { "type": "string", "enum": ["valid_time", "transaction_time", "bitemporal"] },
                  "coordinate_names": {
                    "type": "array",
                    "items": { "type": "string" }
                  }
                }
              }
            }
          }
        }
      }
    },
    "schema_descriptor": {
      "type": "object",
      "required": ["migrations", "trait_bounds"],
      "properties": {
        "migrations": { "type": "array" },
        "trait_bounds": { "type": "array" }
      }
    },
    "schema_version": {
      "type": "string"
    },
    "diagnostics": {
      "type": "array"
    },
    "warnings": {
      "type": "array"
    }
  }
}
```

---

## 2. Compatibility Metadata (`compatibility_metadata.json`)

The compatibility metadata file defines runtime-specific configuration policies, execution status mappings, and load-time/evaluate-time refusal criteria.

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "IgniterCompatibilityMetadata",
  "type": "object",
  "required": [
    "kind",
    "format_version",
    "canonical_artifact",
    "canonical_semantic_ir_ref",
    "compilation_report_ref",
    "loader_shape"
  ],
  "properties": {
    "kind": {
      "type": "string",
      "const": "igapp_compatibility_metadata"
    },
    "format_version": {
      "type": "string"
    },
    "canonical_artifact": {
      "type": "string",
      "const": "semantic_ir_program.json"
    },
    "canonical_semantic_ir_ref": {
      "type": "string",
      "pattern": "^semanticir/[a-f0-9]{16}$"
    },
    "compilation_report_ref": {
      "type": "string",
      "pattern": "^compilation_report/[a-f0-9]{16}$"
    },
    "loader_shape": {
      "type": "string"
    },
    "notes": {
      "type": "array",
      "items": {
        "type": "string"
      }
    },
    "runtime_compatibility_artifact": {
      "type": ["string", "null"]
    },
    "runtime_execution": {
      "type": "object",
      "required": ["status", "guard_policy", "guard_at", "load", "evaluate"],
      "properties": {
        "status": {
          "type": "string",
          "enum": ["supported", "unsupported", "restricted"]
        },
        "guard_policy": {
          "type": "string"
        },
        "guard_at": {
          "type": "string",
          "enum": ["load", "evaluate"]
        },
        "load": {
          "type": "object",
          "required": ["decision"],
          "properties": {
            "decision": { "type": "string" },
            "requires_contract_index": { "type": "boolean" }
          }
        },
        "evaluate": {
          "type": "object",
          "required": ["decision"],
          "properties": {
            "decision": { "type": "string" },
            "reason_code": { "type": "string" }
          }
        }
      }
    }
  }
}
```

---

## 3. Assembled Contract Specification (`contracts/*.json`)

Each file inside the `contracts/` directory represents a compiled, monomorphic contract IR with explicit compute nodes, temporal node mappings, stream window declarations, and escape sets.

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "IgniterContractIR",
  "type": "object",
  "required": [
    "contract_id",
    "source_contract_ref",
    "fragment_class",
    "input_ports",
    "output_ports",
    "compute_nodes"
  ],
  "properties": {
    "contract_id": {
      "type": "string"
    },
    "name": {
      "type": "string"
    },
    "source_contract_ref": {
      "type": "string",
      "pattern": "^contract/[A-Za-z0-9_]+/sha256:[a-f0-9]{24}$"
    },
    "fragment_class": {
      "type": "string",
      "enum": ["core", "stream", "temporal", "escape"]
    },
    "lifecycle": {
      "type": "string",
      "enum": ["local", "session", "window", "durable"]
    },
    "artifact_hash": {
      "type": "string",
      "pattern": "^sha256:[a-f0-9]{64}$"
    },
    "input_ports": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["name", "type_tag", "lifecycle"],
        "properties": {
          "name": { "type": "string" },
          "type_tag": { "type": "string" },
          "lifecycle": { "type": "string" },
          "required": { "type": "boolean" }
        }
      }
    },
    "output_ports": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["name", "type_tag", "lifecycle"],
        "properties": {
          "name": { "type": "string" },
          "type_tag": { "type": "string" },
          "lifecycle": { "type": "string" },
          "required": { "type": "boolean" }
        }
      }
    },
    "compute_nodes": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["kind", "name", "node_id", "dependencies", "expression", "fragment_class", "lifecycle", "obs_kind"],
        "properties": {
          "kind": { "type": "string", "const": "compute" },
          "name": { "type": "string" },
          "node_id": { "type": "string" },
          "dependencies": {
            "type": "array",
            "items": { "type": "string" }
          },
          "expression": {
            "type": "object",
            "required": ["kind"]
          },
          "fragment_class": {
            "type": "string",
            "enum": ["core", "stream", "temporal", "escape"]
          },
          "lifecycle": { "type": "string" },
          "obs_kind": { "type": "string" },
          "type_tag": { "type": "string" }
        }
      }
    },
    "temporal_nodes": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["kind", "name", "required_capability", "required_caps", "obs_kind"],
        "properties": {
          "kind": {
            "type": "string",
            "enum": ["temporal_input_node", "temporal_access_node"]
          },
          "name": { "type": "string" },
          "type_tag": { "type": "string" },
          "axis": { "type": "string" },
          "store_ref": { "type": "string" },
          "temporal_axis": { "type": "string" },
          "coordinate_refs": { "type": "object" },
          "required_capability": { "type": "string" },
          "required_caps": {
            "type": "array",
            "items": { "type": "string" }
          },
          "obs_kind": { "type": "string" }
        }
      }
    },
    "stream_nodes": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["kind", "obs_kind"],
        "properties": {
          "kind": {
            "type": "string",
            "enum": ["stream_input_node", "window_decl_node", "fold_stream_node"]
          },
          "name": { "type": "string" },
          "ref": { "type": "string" },
          "window_kind": { "type": "string" },
          "size": { "type": "integer" },
          "bounded": { "type": "boolean" },
          "on_close": { "type": "string" },
          "init": { "type": "object" },
          "fn_ref": { "type": "string" },
          "bound": { "type": "object" },
          "event_binding": { "type": "object" },
          "obs_kind": { "type": "string" }
        }
      }
    },
    "escape_set": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["name", "required_caps", "produces"],
        "properties": {
          "name": { "type": "string" },
          "required_caps": {
            "type": "array",
            "items": { "type": "string" }
          },
          "produces": {
            "type": "array",
            "items": { "type": "string" }
          }
        }
      }
    },
    "type_signature": {
      "type": "object",
      "required": ["inputs", "outputs"],
      "properties": {
        "inputs": {
          "type": "object",
          "additionalProperties": { "type": "string" }
        },
        "outputs": {
          "type": "object",
          "additionalProperties": { "type": "string" }
        }
      }
    }
  }
}
```
