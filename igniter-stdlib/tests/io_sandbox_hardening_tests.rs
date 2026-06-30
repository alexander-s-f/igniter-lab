use igniter_stdlib::io::{stdlib_io_free_string, stdlib_io_write_text, IOCapability};
use serde_json::Value;
use std::ffi::{CStr, CString};
use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

fn unique_dir(label: &str) -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let dir = std::env::temp_dir().join(format!(
        "igniter-stdlib-io-sandbox-{}-{}-{}",
        label,
        std::process::id(),
        nanos
    ));
    fs::create_dir_all(&dir).unwrap();
    dir
}

fn capability(sandbox_dir: PathBuf) -> IOCapability {
    IOCapability {
        capability_id: "cap-io-hardening".to_string(),
        sandbox_dir: sandbox_dir.to_string_lossy().into_owned(),
        allowed_absolute_paths: None,
        read_allowed: true,
        write_allowed: true,
    }
}

fn write_text(path: &str, content: &str, cap: &IOCapability) -> Value {
    let path = CString::new(path).unwrap();
    let content = CString::new(content).unwrap();
    let cap = CString::new(serde_json::to_string(cap).unwrap()).unwrap();
    let result = stdlib_io_write_text(path.as_ptr(), content.as_ptr(), cap.as_ptr());
    let result_json = unsafe { CStr::from_ptr(result).to_string_lossy().into_owned() };
    stdlib_io_free_string(result);
    serde_json::from_str(&result_json).unwrap()
}

#[test]
fn normal_write_inside_sandbox_succeeds() {
    let root = unique_dir("normal");
    let sandbox = root.join("sandbox");
    fs::create_dir_all(&sandbox).unwrap();
    let cap = capability(sandbox.clone());

    let result = write_text("nested/ok.txt", "inside", &cap);

    assert!(result.get("ok").is_some(), "{result:?}");
    assert_eq!(
        fs::read_to_string(sandbox.join("nested/ok.txt")).unwrap(),
        "inside"
    );
}

#[test]
fn substring_named_path_outside_sandbox_is_refused() {
    let root = unique_dir("substring");
    let sandbox = root.join("sandbox");
    fs::create_dir_all(&sandbox).unwrap();
    let outside = root.join("outside-igniter-stdlib").join("out");
    fs::create_dir_all(&outside).unwrap();
    let cap = capability(sandbox);

    let result = write_text("../outside-igniter-stdlib/out/escape.txt", "escape", &cap);

    assert_eq!(result["err"]["error_type"], "PathTraversal");
    assert!(!outside.join("escape.txt").exists());
}

#[cfg(unix)]
#[test]
fn write_through_symlink_target_is_refused() {
    let root = unique_dir("symlink-target");
    let sandbox = root.join("sandbox");
    let outside = root.join("outside");
    fs::create_dir_all(&sandbox).unwrap();
    fs::create_dir_all(&outside).unwrap();
    let outside_file = outside.join("target.txt");
    fs::write(&outside_file, "outside").unwrap();
    std::os::unix::fs::symlink(&outside_file, sandbox.join("link.txt")).unwrap();
    let cap = capability(sandbox);

    let result = write_text("link.txt", "escape", &cap);

    assert_eq!(result["err"]["error_type"], "PathTraversal");
    assert_eq!(fs::read_to_string(outside_file).unwrap(), "outside");
}

#[cfg(unix)]
#[test]
fn missing_target_under_symlink_parent_escape_is_refused() {
    let root = unique_dir("symlink-parent");
    let sandbox = root.join("sandbox");
    let outside = root.join("outside");
    fs::create_dir_all(&sandbox).unwrap();
    fs::create_dir_all(&outside).unwrap();
    std::os::unix::fs::symlink(&outside, sandbox.join("linked-parent")).unwrap();
    let cap = capability(sandbox);

    let result = write_text("linked-parent/escape.txt", "escape", &cap);

    assert_eq!(result["err"]["error_type"], "PathTraversal");
    assert!(!outside.join("escape.txt").exists());
}
