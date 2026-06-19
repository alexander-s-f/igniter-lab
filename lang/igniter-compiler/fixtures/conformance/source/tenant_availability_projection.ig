-- tenant_availability_projection.ig
-- Parser acceptance fixture: scoped_by, cardinality, schema_version, tenant_free.
-- Compiler acceptance target: fixtures/tenant_availability_projection.igapp/
-- Grammar version: spark-pipeline-v0

module SparkCRM.Availability

import SparkCRM.Types.{
  TechnicianProfile, ScheduleSlotObservation,
  OffScheduleBlock, DayOffConfigVersion, AvailabilitySnapshot, TimeSlot, TenantScope
}

observed contract TenantAvailabilityProjection {
  input technician_id: String
  input date: String
  input company_scope: TenantScope

  escape scoped_tbackend_read

  read technician: TechnicianProfile
    from "technician/{technician_id}"
    lifecycle :durable
    scoped_by company_scope
    cardinality 1..1
    schema_version "technician-profile-v1"

  read schedules: Collection[ScheduleSlotObservation]
    from "schedule/{technician_id}/{date}"
    lifecycle :durable
    scoped_by company_scope
    cardinality 0..500
    schema_version "schedule-slot-v1"

  read off_schedules: Collection[OffScheduleBlock]
    from "off_schedule/{technician_id}/{date}"
    lifecycle :window
    scoped_by company_scope
    cardinality 0..200
    schema_version "off-schedule-v1"

  read day_off_config: DayOffConfigVersion
    from "day_off_config/{technician_id}"
    lifecycle :durable
    scoped_by company_scope
    cardinality 0..1
    schema_version "day-off-config-v1"

  compute available_slots = compute_availability(
    technician, schedules, off_schedules, day_off_config, date
  )

  snapshot snap = build_snapshot(available_slots, technician_id, date)
    lifecycle :durable

  output available_slots: Collection[TimeSlot]  lifecycle :window
  output snap: AvailabilitySnapshot             lifecycle :durable
}
