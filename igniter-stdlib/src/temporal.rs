// src/temporal.rs
// Temporal and scheduling helper candidates for lab proofs

use serde_json::{Value, json};

// Computes available slots based on dynamic geo-signals and schedule facts
pub fn compute_availability(geo_signals: &Value, schedule: &Value) -> Result<Value, String> {
    let day_off = schedule
        .get("day_off")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);

    if day_off {
        return Ok(Value::Array(Vec::new()));
    }

    let working_hours = schedule
        .get("working_hours")
        .and_then(|v| v.as_array())
        .ok_or_else(|| "Missing or invalid 'working_hours' in schedule".to_string())?;

    if working_hours.len() < 2 {
        return Err("Invalid 'working_hours' bounds".to_string());
    }

    let start_h = working_hours[0]
        .as_i64()
        .ok_or_else(|| "Invalid start_hour".to_string())?;
    let end_h = working_hours[1]
        .as_i64()
        .ok_or_else(|| "Invalid end_hour".to_string())?;

    let geo_signals_arr = geo_signals
        .as_array()
        .ok_or_else(|| "Missing or invalid 'geo_signals' collection".to_string())?;

    let mut slots = Vec::new();
    for hour in start_h..end_h {
        let sig = geo_signals_arr
            .iter()
            .find(|s| s.get("hour").and_then(|v| v.as_i64()) == Some(hour));

        let status = match sig {
            Some(s) => s.get("signal").and_then(|v| v.as_str()).unwrap_or("available"),
            None => "available",
        };

        slots.push(json!({
            "hour": hour,
            "status": status
        }));
    }

    Ok(Value::Array(slots))
}

// Builds an availability snapshot fact with count aggregation
pub fn build_snapshot(slots: &Value, technician_id: &str, date: &str) -> Result<Value, String> {
    let slots_arr = slots
        .as_array()
        .ok_or_else(|| "Missing or invalid 'slots' collection".to_string())?;

    let available_count = slots_arr
        .iter()
        .filter(|s| s.get("status").and_then(|v| v.as_str()) == Some("available"))
        .count();

    Ok(json!({
        "technician_id": technician_id,
        "date": date,
        "available_slots": slots,
        "available_count": available_count,
        "snapshot_at": date
    }))
}
