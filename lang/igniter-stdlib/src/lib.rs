// src/lib.rs
// Entrypoint for the Igniter Standard Library (igniter-stdlib)

pub const VERSION: &str = env!("CARGO_PKG_VERSION");

pub mod collections;
pub mod decimal;
pub mod io;
pub mod temporal;

// Expose FFI compatible entrypoint for Decimal addition
#[no_mangle]
pub extern "C" fn stdlib_decimal_add(
    a_val: i64,
    a_scale: u32,
    b_val: i64,
    b_scale: u32,
    out_val: *mut i64,
    out_scale: *mut u32,
) -> i32 {
    let a = decimal::Decimal::new(a_val, a_scale);
    let b = decimal::Decimal::new(b_val, b_scale);

    match a.add(&b) {
        Ok(res) => unsafe {
            *out_val = res.value;
            *out_scale = res.scale;
            0
        },
        Err(_) => 1, // Scale mismatch error code
    }
}

// Expose FFI compatible entrypoint for Decimal subtraction
#[no_mangle]
pub extern "C" fn stdlib_decimal_sub(
    a_val: i64,
    a_scale: u32,
    b_val: i64,
    b_scale: u32,
    out_val: *mut i64,
    out_scale: *mut u32,
) -> i32 {
    let a = decimal::Decimal::new(a_val, a_scale);
    let b = decimal::Decimal::new(b_val, b_scale);

    match a.sub(&b) {
        Ok(res) => unsafe {
            *out_val = res.value;
            *out_scale = res.scale;
            0
        },
        Err(_) => 1, // Scale mismatch error code
    }
}

// Expose FFI compatible entrypoint for Decimal multiplication
#[no_mangle]
pub extern "C" fn stdlib_decimal_mul(
    a_val: i64,
    a_scale: u32,
    b_val: i64,
    b_scale: u32,
    out_val: *mut i64,
    out_scale: *mut u32,
) {
    let a = decimal::Decimal::new(a_val, a_scale);
    let b = decimal::Decimal::new(b_val, b_scale);
    let res = a.mul(&b);
    unsafe {
        *out_val = res.value;
        *out_scale = res.scale;
    }
}

// Expose FFI compatible entrypoint for Decimal division
#[no_mangle]
pub extern "C" fn stdlib_decimal_div(
    a_val: i64,
    a_scale: u32,
    b_val: i64,
    b_scale: u32,
    out_val: *mut i64,
    out_scale: *mut u32,
) -> i32 {
    let a = decimal::Decimal::new(a_val, a_scale);
    let b = decimal::Decimal::new(b_val, b_scale);

    match a.div(&b) {
        Ok(res) => unsafe {
            *out_val = res.value;
            *out_scale = res.scale;
            0
        },
        Err(_) => 2, // Division error code (e.g. division by zero or scale underflow)
    }
}
