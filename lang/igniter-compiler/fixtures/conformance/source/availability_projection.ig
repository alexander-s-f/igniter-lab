-- availability_projection.ig
-- ESCAPE contract with window lifecycle, TBackend reads, user-defined defs
-- Compiler acceptance target: fixtures/availability_projection.igapp/

module SparkCRM.Availability

import SparkCRM.Types.{ GeoSignal, TimeSlot, ScheduleFact, AvailabilitySnapshot }

def compute_slots(geo_signals: Collection[GeoSignal], schedule: ScheduleFact)
    -> Collection[TimeSlot] {
  if schedule.day_off {
    []
  } else {
    let start = schedule.working_hours[0]
    let end   = schedule.working_hours[1]
    fold(range(start, end), [], (acc, hour) -> {
      let sig    = filter(geo_signals, s -> s.hour == hour)
      let status = or_else(first(map(sig, s -> s.signal)), "available")
      acc ++ [{ hour: hour, status: status }]
    })
  }
}

def build_snapshot(slots: Collection[TimeSlot], technician_id: String, date: String)
    -> AvailabilitySnapshot {
  let available_count = count(filter(slots, s -> s.status == "available"))
  {
    technician_id:   technician_id,
    date:            date,
    available_slots: slots,
    available_count: available_count,
    snapshot_at:     date
  }
}

observed contract AvailabilityProjection {
  input technician_id: String
  input date: String

  escape stream_collection

  read geo_signals: Collection[GeoSignal]
    from "geo_signal/{technician_id}/{date}"
    lifecycle :window

  read schedule: ScheduleFact
    from "schedule/{technician_id}/{date}"
    lifecycle :durable

  compute available_slots = compute_slots(geo_signals, schedule)

  window "availability[technician, day]" {
    kind     :calendar
    unit     :day
    on_close :snapshot
  }

  snapshot snap = build_snapshot(available_slots, technician_id, date)
    lifecycle :durable

  output available_slots: Collection[TimeSlot]  lifecycle :window
  output snap: AvailabilitySnapshot             lifecycle :durable
}
