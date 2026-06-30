use igniter_stdlib::decimal::{Decimal, MAX_DECIMAL_SCALE};
use std::cmp::Ordering;

#[test]
fn checked_add_sub_mul_do_not_wrap() {
    assert!(Decimal::new(i64::MAX, 0)
        .add(&Decimal::new(1, 0))
        .unwrap_err()
        .contains("OOF-DM1"));
    assert!(Decimal::new(i64::MIN, 0)
        .sub(&Decimal::new(1, 0))
        .unwrap_err()
        .contains("OOF-DM1"));
    assert!(Decimal::new(i64::MAX, 0)
        .mul(&Decimal::new(2, 0))
        .unwrap_err()
        .contains("OOF-DM1"));
}

#[test]
fn scale_bound_and_scale_overflow_fail_closed() {
    assert_eq!(MAX_DECIMAL_SCALE, 18);
    assert!(Decimal::checked_new(1, 19).unwrap_err().contains("OOF-DM4"));
    assert!(Decimal::new(1, 10)
        .mul(&Decimal::new(1, 9))
        .unwrap_err()
        .contains("OOF-DM4"));
}

#[test]
fn decimal_order_is_scale_normalized_and_exact() {
    assert_eq!(
        Decimal::new(15, 1).cmp_decimal(&Decimal::new(150, 2)),
        Ok(Ordering::Equal)
    );
    assert_eq!(
        Decimal::new(10, 1).cmp_decimal(&Decimal::new(5, 0)),
        Ok(Ordering::Less)
    );
    assert_eq!(
        Decimal::new(9_007_199_254_740_993, 0).cmp_decimal(&Decimal::new(9_007_199_254_740_992, 0)),
        Ok(Ordering::Greater)
    );
}

#[test]
fn exact_division_preserves_lhs_scale_and_inexact_division_errors() {
    assert_eq!(
        Decimal::new(2625, 2).div(&Decimal::new(25, 1)),
        Ok(Decimal::new(1050, 2))
    );
    assert!(Decimal::new(1000, 2)
        .div(&Decimal::new(300, 2))
        .unwrap_err()
        .contains("OOF-DM3"));
    assert!(Decimal::new(1000, 2)
        .div(&Decimal::new(0, 2))
        .unwrap_err()
        .contains("OOF-DM2"));
}
