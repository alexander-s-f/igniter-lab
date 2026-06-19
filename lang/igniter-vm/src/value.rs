// src/value.rs
// FFI-oriented, Arc-shared value representation for lab VM execution

use std::sync::Arc;

#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Nil,
    Bool(bool),
    Integer(i64),
    Float(f64),
    String(Arc<str>),
    Decimal { value: i64, scale: u32 },
    Array(Arc<Vec<Value>>),
    Record(Arc<std::collections::BTreeMap<String, Value>>),
}

impl Value {
    pub fn is_decimal(&self) -> bool {
        matches!(self, Value::Decimal { .. })
    }

    pub fn as_bool(&self) -> Result<bool, String> {
        match self {
            Value::Bool(b) => Ok(*b),
            _ => Err(format!("Expected Bool, got: {:?}", self)),
        }
    }

    pub fn as_str(&self) -> Result<&str, String> {
        match self {
            Value::String(s) => Ok(s),
            _ => Err(format!("Expected String, got: {:?}", self)),
        }
    }

    pub fn as_integer(&self) -> Result<i64, String> {
        match self {
            Value::Integer(i) => Ok(*i),
            _ => Err(format!("Expected Integer, got: {:?}", self)),
        }
    }

    pub fn as_decimal(&self) -> Result<(i64, u32), String> {
        match self {
            Value::Decimal { value, scale } => Ok((*value, *scale)),
            _ => Err(format!("Expected Decimal, got: {:?}", self)),
        }
    }

    pub fn from_json(jv: &serde_json::Value) -> Self {
        match jv {
            serde_json::Value::Null => Value::Nil,
            serde_json::Value::Bool(b) => Value::Bool(*b),
            serde_json::Value::Number(num) => {
                if let Some(i) = num.as_i64() {
                    Value::Integer(i)
                } else if let Some(f) = num.as_f64() {
                    Value::Float(f)
                } else {
                    Value::Nil
                }
            }
            serde_json::Value::String(s) => Value::String(Arc::from(s.as_str())),
            serde_json::Value::Array(arr) => {
                let parsed: Vec<Value> = arr.iter().map(Value::from_json).collect();
                Value::Array(Arc::new(parsed))
            }
            serde_json::Value::Object(obj) => {
                // Key-neutral bitemporal Decimal detection (supporting symbolized/string keys)
                let val_key = if obj.contains_key("value") {
                    Some("value")
                } else {
                    None
                };
                let scale_key = if obj.contains_key("scale") {
                    Some("scale")
                } else {
                    None
                };

                if let (Some(vk), Some(sk)) = (val_key, scale_key) {
                    if let (Some(val_num), Some(scale_num)) = (obj.get(vk), obj.get(sk)) {
                        if let (Some(v), Some(s)) = (val_num.as_i64(), scale_num.as_u64()) {
                            return Value::Decimal {
                                value: v,
                                scale: s as u32,
                            };
                        }
                    }
                }
                let mut map = std::collections::BTreeMap::new();
                for (k, v) in obj {
                    map.insert(k.clone(), Value::from_json(v));
                }
                Value::Record(Arc::new(map))
            }
        }
    }

    pub fn to_json(&self) -> serde_json::Value {
        match self {
            Value::Nil => serde_json::Value::Null,
            Value::Bool(b) => serde_json::Value::Bool(*b),
            Value::Integer(i) => serde_json::Value::Number((*i).into()),
            Value::Float(f) => serde_json::Value::from(*f),
            Value::String(s) => serde_json::Value::String(s.to_string()),
            Value::Decimal { value, scale } => {
                let mut map = serde_json::Map::new();
                map.insert(
                    "value".to_string(),
                    serde_json::Value::Number((*value).into()),
                );
                map.insert(
                    "scale".to_string(),
                    serde_json::Value::Number((*scale).into()),
                );
                serde_json::Value::Object(map)
            }
            Value::Array(arr) => {
                let list: Vec<serde_json::Value> = arr.iter().map(|v| v.to_json()).collect();
                serde_json::Value::Array(list)
            }
            Value::Record(map) => {
                let mut obj = serde_json::Map::new();
                for (k, v) in map.iter() {
                    obj.insert(k.clone(), v.to_json());
                }
                serde_json::Value::Object(obj)
            }
        }
    }
}
