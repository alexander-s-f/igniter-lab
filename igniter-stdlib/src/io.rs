// src/io.rs
// Experimental capability-bound C ABI I/O candidate implementation

use serde_json::{json, Value};
use std::ffi::{CStr, CString};
use std::fs;
use std::os::raw::c_char;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct IOCapability {
    pub capability_id: String,
    pub sandbox_dir: String,
    pub allowed_absolute_paths: Option<Vec<String>>,
    pub read_allowed: bool,
    pub write_allowed: bool,
}

// Lexically clean paths to handle '..' and '.' without hits to the filesystem
fn clean_path(path: &Path) -> PathBuf {
    use std::path::Component;
    let mut result = PathBuf::new();
    for component in path.components() {
        match component {
            Component::Prefix(_) => {
                result.push(component);
            }
            Component::RootDir => {
                result.push(component);
            }
            Component::CurDir => {}
            Component::ParentDir => {
                result.pop();
            }
            Component::Normal(c) => {
                result.push(c);
            }
        }
    }
    result
}

// Validates requested path according to capability policies and sandboxing rules
pub fn validate_path(
    path_str: &str,
    cap: &IOCapability,
    is_write: bool,
) -> Result<PathBuf, String> {
    // 1. Check capability permissions
    if is_write && !cap.write_allowed {
        return Err("CapabilityError: write operation not permitted by capability".to_string());
    }
    if !is_write && !cap.read_allowed {
        return Err("CapabilityError: read operation not permitted by capability".to_string());
    }

    let req_path = Path::new(path_str);

    // 2. Resolve sandbox_dir to absolute canonical path
    let base_sandbox = Path::new(&cap.sandbox_dir);
    let abs_sandbox = if base_sandbox.is_absolute() {
        base_sandbox.to_path_buf()
    } else {
        std::env::current_dir()
            .map(|cwd| cwd.join(base_sandbox))
            .map_err(|e| format!("Failed to resolve current directory: {}", e))?
    };

    if !abs_sandbox.exists() {
        fs::create_dir_all(&abs_sandbox)
            .map_err(|e| format!("Failed to create sandbox directory: {}", e))?;
    }

    let abs_sandbox = fs::canonicalize(&abs_sandbox)
        .map_err(|e| format!("Failed to canonicalize sandbox path: {}", e))?;

    // 3. Absolute path checks (must fail closed unless explicitly mapped)
    if req_path.is_absolute() {
        if let Some(ref allowed) = cap.allowed_absolute_paths {
            let matched = allowed.iter().any(|allowed_p| {
                let allowed_path = Path::new(allowed_p);
                if let (Ok(c_req), Ok(c_allowed)) =
                    (fs::canonicalize(req_path), fs::canonicalize(allowed_path))
                {
                    c_req == c_allowed
                } else {
                    req_path == allowed_path
                }
            });
            if !matched {
                return Err(
                    "CapabilityError: absolute path not explicitly mapped by capability"
                        .to_string(),
                );
            }
            return Ok(req_path.to_path_buf());
        } else {
            return Err("CapabilityError: absolute paths are blocked by default".to_string());
        }
    }

    // 4. Relative path check joined with sandbox directory
    let target_path = abs_sandbox.join(req_path);
    let resolved_path = clean_path(&target_path);

    // 5. Fail closed if path traversal escapes the sandbox
    if !resolved_path.starts_with(&abs_sandbox) {
        return Err("PathTraversalError: path traversal outside sandbox detected".to_string());
    }

    if is_write {
        validate_write_target(&resolved_path, &abs_sandbox)?;
    } else if resolved_path.exists() {
        let canonical = fs::canonicalize(&resolved_path)
            .map_err(|e| format!("PathTraversalError: failed to canonicalize path: {}", e))?;
        if !canonical.starts_with(&abs_sandbox) {
            return Err("PathTraversalError: canonical path traversal detected".to_string());
        }
    }

    Ok(resolved_path)
}

fn validate_write_target(path: &Path, sandbox_root: &Path) -> Result<(), String> {
    let relative = path.strip_prefix(sandbox_root).map_err(|_| {
        "PathTraversalError: write target outside canonical sandbox root".to_string()
    })?;

    let mut current = sandbox_root.to_path_buf();
    for component in relative.components() {
        current.push(component);
        match fs::symlink_metadata(&current) {
            Ok(metadata) => {
                if metadata.file_type().is_symlink() {
                    return Err("PathTraversalError: write target traverses a symlink".to_string());
                }
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => break,
            Err(e) => {
                return Err(format!(
                    "PathTraversalError: failed to inspect write path component: {}",
                    e
                ))
            }
        }
    }

    let parent = path
        .parent()
        .ok_or_else(|| "PathTraversalError: write target has no parent directory".to_string())?;

    if parent.exists() {
        let canonical_parent = fs::canonicalize(parent).map_err(|e| {
            format!(
                "PathTraversalError: failed to canonicalize write parent: {}",
                e
            )
        })?;
        if !canonical_parent.starts_with(sandbox_root) {
            return Err(
                "PathTraversalError: write parent escapes canonical sandbox root".to_string(),
            );
        }
    } else {
        validate_nearest_existing_parent(parent, sandbox_root)?;
    }

    Ok(())
}

fn validate_nearest_existing_parent(parent: &Path, sandbox_root: &Path) -> Result<(), String> {
    let mut ancestor = parent;
    while !ancestor.exists() {
        ancestor = ancestor.parent().ok_or_else(|| {
            "PathTraversalError: write parent has no existing ancestor".to_string()
        })?;
    }

    let canonical_ancestor = fs::canonicalize(ancestor).map_err(|e| {
        format!(
            "PathTraversalError: failed to canonicalize write ancestor: {}",
            e
        )
    })?;
    if !canonical_ancestor.starts_with(sandbox_root) {
        return Err(
            "PathTraversalError: write parent ancestor escapes canonical sandbox root".to_string(),
        );
    }

    Ok(())
}

// Compute simple FNV-1a non-cryptographic content digest to avoid dependencies
fn fnv1a_digest(content: &[u8]) -> String {
    let mut hash: u64 = 0xcbf29ce484222325;
    for &byte in content {
        hash ^= byte as u64;
        hash = hash.wrapping_mul(0x100000001b3);
    }
    format!("{:016x}", hash)
}

unsafe fn to_rust_str<'a>(ptr: *const c_char) -> Result<&'a str, String> {
    if ptr.is_null() {
        return Err("NullPointerError: argument pointer is null".to_string());
    }
    CStr::from_ptr(ptr)
        .to_str()
        .map_err(|e| format!("Utf8Error: {}", e))
}

fn parse_and_classify_validation_error(err_str: &str, path_str: &str) -> Value {
    let error_type = if err_str.contains("CapabilityError") {
        "CapabilityError"
    } else if err_str.contains("PathTraversalError") || err_str.contains("SandboxSecurityViolation")
    {
        "PathTraversal"
    } else {
        "IoError"
    };
    make_err(error_type, err_str, Some(path_str))
}

fn make_err(error_type: &str, message: &str, path: Option<&str>) -> Value {
    let mut err_obj = json!({
        "error_type": error_type,
        "message": message
    });
    if let Some(p) = path {
        err_obj
            .as_object_mut()
            .unwrap()
            .insert("path".to_string(), json!(p));
    }
    json!({ "err": err_obj })
}

fn to_c_string(val: Value) -> *mut c_char {
    let s = serde_json::to_string(&val).unwrap_or_else(|_| {
        r#"{"err":{"error_type":"InternalError","message":"Serialization failure"}}"#.to_string()
    });
    CString::new(s)
        .unwrap_or_else(|_| {
            CString::new(r#"{"err":{"error_type":"InternalError","message":"Null byte in serialized JSON"}}"#).unwrap()
        })
        .into_raw()
}

// --- FFI EXPORTS (C ABI compatible) ---

#[no_mangle]
pub extern "C" fn stdlib_io_read_text(
    path_ptr: *const c_char,
    cap_ptr: *const c_char,
) -> *mut c_char {
    let result = unsafe { read_text_impl(path_ptr, cap_ptr) };
    to_c_string(result)
}

#[no_mangle]
pub extern "C" fn stdlib_io_write_text(
    path_ptr: *const c_char,
    content_ptr: *const c_char,
    cap_ptr: *const c_char,
) -> *mut c_char {
    let result = unsafe { write_text_impl(path_ptr, content_ptr, cap_ptr) };
    to_c_string(result)
}

#[no_mangle]
pub extern "C" fn stdlib_io_read_json(
    path_ptr: *const c_char,
    cap_ptr: *const c_char,
) -> *mut c_char {
    let result = unsafe { read_json_impl(path_ptr, cap_ptr) };
    to_c_string(result)
}

#[no_mangle]
pub extern "C" fn stdlib_io_write_json(
    path_ptr: *const c_char,
    value_ptr: *const c_char,
    cap_ptr: *const c_char,
) -> *mut c_char {
    let result = unsafe { write_json_impl(path_ptr, value_ptr, cap_ptr) };
    to_c_string(result)
}

#[no_mangle]
pub extern "C" fn stdlib_io_exists(path_ptr: *const c_char, cap_ptr: *const c_char) -> *mut c_char {
    let result = unsafe { exists_impl(path_ptr, cap_ptr) };
    to_c_string(result)
}

#[no_mangle]
pub extern "C" fn stdlib_io_list_dir(
    path_ptr: *const c_char,
    cap_ptr: *const c_char,
) -> *mut c_char {
    let result = unsafe { list_dir_impl(path_ptr, cap_ptr) };
    to_c_string(result)
}

#[no_mangle]
pub extern "C" fn stdlib_io_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

// --- IMPL IMPLEMENTATIONS ---

unsafe fn read_text_impl(path_ptr: *const c_char, cap_ptr: *const c_char) -> Value {
    let path_str = match to_rust_str(path_ptr) {
        Ok(s) => s,
        Err(e) => return make_err("CapabilityError", &e, None),
    };
    let cap_json = match to_rust_str(cap_ptr) {
        Ok(s) => s,
        Err(e) => return make_err("CapabilityError", &e, None),
    };
    let cap: IOCapability = match serde_json::from_str(cap_json) {
        Ok(c) => c,
        Err(e) => {
            return make_err(
                "CapabilityError",
                &format!("Malformed capability: {}", e),
                None,
            )
        }
    };

    let resolved_path = match validate_path(path_str, &cap, false) {
        Ok(p) => p,
        Err(e) => return parse_and_classify_validation_error(&e, path_str),
    };

    if !resolved_path.exists() {
        return make_err(
            "FileNotFound",
            &format!("File not found: {}", path_str),
            Some(path_str),
        );
    }
    if !resolved_path.is_file() {
        return make_err(
            "IoError",
            &format!("Path is not a file: {}", path_str),
            Some(path_str),
        );
    }

    match fs::read(&resolved_path) {
        Ok(bytes) => {
            let content = match String::from_utf8(bytes) {
                Ok(s) => s,
                Err(e) => {
                    return make_err("IoError", &format!("Invalid UTF-8: {}", e), Some(path_str))
                }
            };
            let digest = fnv1a_digest(content.as_bytes());
            json!({
                "ok": content,
                "metadata": {
                    "path": path_str,
                    "bytes_read": content.len(),
                    "content_digest": digest,
                    "capability_id": cap.capability_id
                }
            })
        }
        Err(e) => make_err("IoError", &e.to_string(), Some(path_str)),
    }
}

unsafe fn write_text_impl(
    path_ptr: *const c_char,
    content_ptr: *const c_char,
    cap_ptr: *const c_char,
) -> Value {
    let path_str = match to_rust_str(path_ptr) {
        Ok(s) => s,
        Err(e) => return make_err("CapabilityError", &e, None),
    };
    let content = match to_rust_str(content_ptr) {
        Ok(s) => s,
        Err(e) => return make_err("IoError", &e, None),
    };
    let cap_json = match to_rust_str(cap_ptr) {
        Ok(s) => s,
        Err(e) => return make_err("CapabilityError", &e, None),
    };
    let cap: IOCapability = match serde_json::from_str(cap_json) {
        Ok(c) => c,
        Err(e) => {
            return make_err(
                "CapabilityError",
                &format!("Malformed capability: {}", e),
                None,
            )
        }
    };

    let mut resolved_path = match validate_path(path_str, &cap, true) {
        Ok(p) => p,
        Err(e) => return parse_and_classify_validation_error(&e, path_str),
    };

    if let Some(parent) = resolved_path.parent() {
        if !parent.exists() {
            if let Err(e) = fs::create_dir_all(parent) {
                return make_err(
                    "IoError",
                    &format!("Failed to create parent dir: {}", e),
                    Some(path_str),
                );
            }
        }
    }

    resolved_path = match validate_path(path_str, &cap, true) {
        Ok(p) => p,
        Err(e) => return parse_and_classify_validation_error(&e, path_str),
    };

    match fs::write(&resolved_path, content) {
        Ok(_) => {
            let digest = fnv1a_digest(content.as_bytes());
            let timestamp = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs();
            json!({
                "ok": {
                    "path": path_str,
                    "bytes_written": content.len(),
                    "content_digest": digest,
                    "timestamp": timestamp,
                    "capability_id": cap.capability_id
                }
            })
        }
        Err(e) => make_err("IoError", &e.to_string(), Some(path_str)),
    }
}

unsafe fn read_json_impl(path_ptr: *const c_char, cap_ptr: *const c_char) -> Value {
    let path_str = match to_rust_str(path_ptr) {
        Ok(s) => s,
        Err(e) => return make_err("CapabilityError", &e, None),
    };
    let cap_json = match to_rust_str(cap_ptr) {
        Ok(s) => s,
        Err(e) => return make_err("CapabilityError", &e, None),
    };
    let cap: IOCapability = match serde_json::from_str(cap_json) {
        Ok(c) => c,
        Err(e) => {
            return make_err(
                "CapabilityError",
                &format!("Malformed capability: {}", e),
                None,
            )
        }
    };

    let resolved_path = match validate_path(path_str, &cap, false) {
        Ok(p) => p,
        Err(e) => return parse_and_classify_validation_error(&e, path_str),
    };

    if !resolved_path.exists() {
        return make_err(
            "FileNotFound",
            &format!("File not found: {}", path_str),
            Some(path_str),
        );
    }
    if !resolved_path.is_file() {
        return make_err(
            "IoError",
            &format!("Path is not a file: {}", path_str),
            Some(path_str),
        );
    }

    match fs::read_to_string(&resolved_path) {
        Ok(content) => {
            let parsed: Value = match serde_json::from_str(&content) {
                Ok(v) => v,
                Err(e) => {
                    return make_err(
                        "InvalidJson",
                        &format!("Invalid JSON: {}", e),
                        Some(path_str),
                    )
                }
            };
            let digest = fnv1a_digest(content.as_bytes());
            json!({
                "ok": parsed,
                "metadata": {
                    "path": path_str,
                    "bytes_read": content.len(),
                    "content_digest": digest,
                    "capability_id": cap.capability_id
                }
            })
        }
        Err(e) => make_err("IoError", &e.to_string(), Some(path_str)),
    }
}

unsafe fn write_json_impl(
    path_ptr: *const c_char,
    value_ptr: *const c_char,
    cap_ptr: *const c_char,
) -> Value {
    let path_str = match to_rust_str(path_ptr) {
        Ok(s) => s,
        Err(e) => return make_err("CapabilityError", &e, None),
    };
    let value_str = match to_rust_str(value_ptr) {
        Ok(s) => s,
        Err(e) => return make_err("IoError", &e, None),
    };
    let cap_json = match to_rust_str(cap_ptr) {
        Ok(s) => s,
        Err(e) => return make_err("CapabilityError", &e, None),
    };
    let cap: IOCapability = match serde_json::from_str(cap_json) {
        Ok(c) => c,
        Err(e) => {
            return make_err(
                "CapabilityError",
                &format!("Malformed capability: {}", e),
                None,
            )
        }
    };

    let mut resolved_path = match validate_path(path_str, &cap, true) {
        Ok(p) => p,
        Err(e) => return parse_and_classify_validation_error(&e, path_str),
    };

    let parsed_val: Value = match serde_json::from_str(value_str) {
        Ok(v) => v,
        Err(e) => {
            return make_err(
                "InvalidJson",
                &format!("Input value is not valid JSON: {}", e),
                Some(path_str),
            )
        }
    };

    let content = match serde_json::to_string_pretty(&parsed_val) {
        Ok(s) => s,
        Err(e) => {
            return make_err(
                "IoError",
                &format!("Failed to serialize JSON: {}", e),
                Some(path_str),
            )
        }
    };

    if let Some(parent) = resolved_path.parent() {
        if !parent.exists() {
            if let Err(e) = fs::create_dir_all(parent) {
                return make_err(
                    "IoError",
                    &format!("Failed to create parent dir: {}", e),
                    Some(path_str),
                );
            }
        }
    }

    resolved_path = match validate_path(path_str, &cap, true) {
        Ok(p) => p,
        Err(e) => return parse_and_classify_validation_error(&e, path_str),
    };

    match fs::write(&resolved_path, &content) {
        Ok(_) => {
            let digest = fnv1a_digest(content.as_bytes());
            let timestamp = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs();
            json!({
                "ok": {
                    "path": path_str,
                    "bytes_written": content.len(),
                    "content_digest": digest,
                    "timestamp": timestamp,
                    "capability_id": cap.capability_id
                }
            })
        }
        Err(e) => make_err("IoError", &e.to_string(), Some(path_str)),
    }
}

unsafe fn exists_impl(path_ptr: *const c_char, cap_ptr: *const c_char) -> Value {
    let path_str = match to_rust_str(path_ptr) {
        Ok(s) => s,
        Err(e) => return make_err("CapabilityError", &e, None),
    };
    let cap_json = match to_rust_str(cap_ptr) {
        Ok(s) => s,
        Err(e) => return make_err("CapabilityError", &e, None),
    };
    let cap: IOCapability = match serde_json::from_str(cap_json) {
        Ok(c) => c,
        Err(e) => {
            return make_err(
                "CapabilityError",
                &format!("Malformed capability: {}", e),
                None,
            )
        }
    };

    let resolved_path = match validate_path(path_str, &cap, false) {
        Ok(p) => p,
        Err(e) => return parse_and_classify_validation_error(&e, path_str),
    };

    json!({
        "ok": resolved_path.exists(),
        "metadata": {
            "path": path_str
        }
    })
}

unsafe fn list_dir_impl(path_ptr: *const c_char, cap_ptr: *const c_char) -> Value {
    let path_str = match to_rust_str(path_ptr) {
        Ok(s) => s,
        Err(e) => return make_err("CapabilityError", &e, None),
    };
    let cap_json = match to_rust_str(cap_ptr) {
        Ok(s) => s,
        Err(e) => return make_err("CapabilityError", &e, None),
    };
    let cap: IOCapability = match serde_json::from_str(cap_json) {
        Ok(c) => c,
        Err(e) => {
            return make_err(
                "CapabilityError",
                &format!("Malformed capability: {}", e),
                None,
            )
        }
    };

    let resolved_path = match validate_path(path_str, &cap, false) {
        Ok(p) => p,
        Err(e) => return parse_and_classify_validation_error(&e, path_str),
    };

    if !resolved_path.exists() {
        return make_err(
            "FileNotFound",
            &format!("Directory not found: {}", path_str),
            Some(path_str),
        );
    }
    if !resolved_path.is_dir() {
        return make_err(
            "IoError",
            &format!("Path is not a directory: {}", path_str),
            Some(path_str),
        );
    }

    match fs::read_dir(&resolved_path) {
        Ok(entries) => {
            let mut result_list = Vec::new();
            for entry in entries {
                if let Ok(entry) = entry {
                    let name = entry.file_name().to_string_lossy().into_owned();
                    let metadata = entry.metadata();
                    let is_dir = metadata.as_ref().map(|m| m.is_dir()).unwrap_or(false);
                    let size_bytes = metadata.as_ref().map(|m| m.len()).unwrap_or(0);
                    result_list.push(json!({
                        "name": name,
                        "is_dir": is_dir,
                        "size_bytes": size_bytes
                    }));
                }
            }
            json!({
                "ok": result_list,
                "metadata": {
                    "path": path_str
                }
            })
        }
        Err(e) => make_err("IoError", &e.to_string(), Some(path_str)),
    }
}
