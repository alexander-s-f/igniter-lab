-- stdlib/temporal.ig
-- Declarative signatures for temporal scheduling helper candidates

module stdlib.Temporal

def compute_availability(geo_signals: Collection[GeoSignal], schedule: ScheduleFact) -> Collection[TimeSlot]
def build_snapshot(slots: Collection[TimeSlot], technician_id: String, date: String) -> AvailabilitySnapshot
