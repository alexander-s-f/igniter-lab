// src/decimal.rs
// Fixed-point Decimal arithmetic candidate for lab VM proofs

use serde::{Serialize, Deserialize};

#[derive(Serialize, Deserialize, Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct Decimal {
    pub value: i64,  // Scaled integer: value = real_value * 10^scale
    pub scale: u32,
}

impl Decimal {
    pub fn new(value: i64, scale: u32) -> Self {
        Decimal { value, scale }
    }

    pub fn to_f64(&self) -> f64 {
        self.value as f64 / 10f64.powi(self.scale as i32)
    }

    pub fn from_f64(val: f64, scale: u32) -> Self {
        let factor = 10f64.powi(scale as i32);
        let int_val = (val * factor).round() as i64;
        Decimal { value: int_val, scale }
    }

    // OOF-TC5: Addition requires matching scales
    pub fn add(&self, other: &Decimal) -> Result<Decimal, String> {
        if self.scale != other.scale {
            return Err(format!(
                "OOF-TC5: Scale mismatch on addition: Decimal[{}] + Decimal[{}]",
                self.scale, other.scale
            ));
        }
        Ok(Decimal::new(self.value + other.value, self.scale))
    }

    // OOF-TC5: Subtraction requires matching scales
    pub fn sub(&self, other: &Decimal) -> Result<Decimal, String> {
        if self.scale != other.scale {
            return Err(format!(
                "OOF-TC5: Scale mismatch on subtraction: Decimal[{}] - Decimal[{}]",
                self.scale, other.scale
            ));
        }
        Ok(Decimal::new(self.value - other.value, self.scale))
    }

    // Multiplication: S1 * S2 -> Result scale = S1 + S2
    pub fn mul(&self, other: &Decimal) -> Decimal {
        Decimal::new(self.value * other.value, self.scale + other.scale)
    }

    // OOF-DM2: Division by zero check. Result scale = S1 - S2
    pub fn div(&self, other: &Decimal) -> Result<Decimal, String> {
        if other.value == 0 {
            return Err("OOF-DM2: Division by zero".to_string());
        }
        if self.scale < other.scale {
            return Err(format!(
                "OOF-DM2: Division scale mismatch: S1 ({}) < S2 ({}) results in negative scale",
                self.scale, other.scale
            ));
        }
        Ok(Decimal::new(self.value / other.value, self.scale - other.scale))
    }
}
