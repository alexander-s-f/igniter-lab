// src/decimal.rs
// Fixed-point Decimal arithmetic candidate for lab VM proofs

use serde::{Deserialize, Serialize};
use std::cmp::Ordering;

pub const MAX_DECIMAL_SCALE: u32 = 18;

#[derive(Serialize, Deserialize, Clone, Copy, Debug)]
pub struct Decimal {
    pub value: i64, // Scaled integer: value = real_value * 10^scale
    pub scale: u32,
}

impl PartialEq for Decimal {
    fn eq(&self, other: &Self) -> bool {
        match self.cmp_decimal(other) {
            Ok(Ordering::Equal) => true,
            Ok(_) => false,
            Err(_) => self.value == other.value && self.scale == other.scale,
        }
    }
}

impl Eq for Decimal {}

impl PartialOrd for Decimal {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        self.cmp_decimal(other).ok()
    }
}

impl Decimal {
    pub fn new(value: i64, scale: u32) -> Self {
        Decimal { value, scale }
    }

    pub fn checked_new(value: i64, scale: u32) -> Result<Self, String> {
        Self::ensure_scale(scale)?;
        Ok(Self::new(value, scale))
    }

    pub fn ensure_scale(scale: u32) -> Result<(), String> {
        if scale > MAX_DECIMAL_SCALE {
            return Err(format!(
                "OOF-DM4: Decimal scale out of range: {} > {}",
                scale, MAX_DECIMAL_SCALE
            ));
        }
        Ok(())
    }

    fn validate(&self) -> Result<(), String> {
        Self::ensure_scale(self.scale)
    }

    fn pow10(scale: u32) -> Result<i128, String> {
        Self::ensure_scale(scale)?;
        10_i128
            .checked_pow(scale)
            .ok_or_else(|| "OOF-DM4: Decimal scale out of range".to_string())
    }

    fn checked_i128_to_i64(value: i128) -> Result<i64, String> {
        i64::try_from(value).map_err(|_| "OOF-DM1: Decimal overflow".to_string())
    }

    pub fn to_f64(&self) -> f64 {
        self.value as f64 / 10f64.powi(self.scale as i32)
    }

    pub fn try_from_f64(val: f64, scale: u32) -> Result<Self, String> {
        Self::ensure_scale(scale)?;
        if !val.is_finite() {
            return Err("OOF-DM6: Float to Decimal conversion is not permitted".to_string());
        }
        let factor = 10f64.powi(scale as i32);
        let scaled = (val * factor).round();
        if !scaled.is_finite() || scaled < i64::MIN as f64 || scaled > i64::MAX as f64 {
            return Err("OOF-DM6: Float to Decimal conversion is not permitted".to_string());
        }
        Ok(Decimal::new(scaled as i64, scale))
    }

    // OOF-TC5: Addition requires matching scales
    pub fn add(&self, other: &Decimal) -> Result<Decimal, String> {
        self.validate()?;
        other.validate()?;
        if self.scale != other.scale {
            return Err(format!(
                "OOF-TC5: Scale mismatch on addition: Decimal[{}] + Decimal[{}]",
                self.scale, other.scale
            ));
        }
        let value = (self.value as i128)
            .checked_add(other.value as i128)
            .ok_or_else(|| "OOF-DM1: Decimal overflow".to_string())?;
        Ok(Decimal::new(Self::checked_i128_to_i64(value)?, self.scale))
    }

    // OOF-TC5: Subtraction requires matching scales
    pub fn sub(&self, other: &Decimal) -> Result<Decimal, String> {
        self.validate()?;
        other.validate()?;
        if self.scale != other.scale {
            return Err(format!(
                "OOF-TC5: Scale mismatch on subtraction: Decimal[{}] - Decimal[{}]",
                self.scale, other.scale
            ));
        }
        let value = (self.value as i128)
            .checked_sub(other.value as i128)
            .ok_or_else(|| "OOF-DM1: Decimal overflow".to_string())?;
        Ok(Decimal::new(Self::checked_i128_to_i64(value)?, self.scale))
    }

    // Multiplication: S1 * S2 -> Result scale = S1 + S2
    pub fn mul(&self, other: &Decimal) -> Result<Decimal, String> {
        self.validate()?;
        other.validate()?;
        let scale = self
            .scale
            .checked_add(other.scale)
            .ok_or_else(|| "OOF-DM5: Decimal scale overflow".to_string())?;
        Self::ensure_scale(scale)?;
        let value = (self.value as i128)
            .checked_mul(other.value as i128)
            .ok_or_else(|| "OOF-DM1: Decimal overflow".to_string())?;
        Ok(Decimal::new(Self::checked_i128_to_i64(value)?, scale))
    }

    // OOF-DM2: Division by zero check. Result scale preserves lhs scale.
    pub fn div(&self, other: &Decimal) -> Result<Decimal, String> {
        self.validate()?;
        other.validate()?;
        if other.value == 0 {
            return Err("OOF-DM2: Division by zero".to_string());
        }
        let rhs_factor = Self::pow10(other.scale)?;
        let numerator = (self.value as i128)
            .checked_mul(rhs_factor)
            .ok_or_else(|| "OOF-DM1: Decimal overflow".to_string())?;
        let denominator = other.value as i128;
        let quotient = numerator / denominator;
        let remainder = numerator % denominator;
        if remainder != 0 {
            return Err(
                "OOF-DM3: Decimal division is inexact; explicit rounding mode required".to_string(),
            );
        }
        Ok(Decimal::new(
            Self::checked_i128_to_i64(quotient)?,
            self.scale,
        ))
    }

    pub fn cmp_decimal(&self, other: &Decimal) -> Result<Ordering, String> {
        self.validate()?;
        other.validate()?;
        let target_scale = self.scale.max(other.scale);
        let lhs_factor = Self::pow10(target_scale - self.scale)?;
        let rhs_factor = Self::pow10(target_scale - other.scale)?;
        let lhs = (self.value as i128)
            .checked_mul(lhs_factor)
            .ok_or_else(|| "OOF-DM1: Decimal overflow".to_string())?;
        let rhs = (other.value as i128)
            .checked_mul(rhs_factor)
            .ok_or_else(|| "OOF-DM1: Decimal overflow".to_string())?;
        Ok(lhs.cmp(&rhs))
    }
}
