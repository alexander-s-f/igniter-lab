-- vendor_lead_pipeline.ig
-- Parser acceptance fixture: pipeline + step keywords.
-- Compiler acceptance target: fixtures/vendor_lead_pipeline.igapp/
-- Grammar version: spark-pipeline-v0

module SparkCRM.Marketing

import SparkCRM.Types.{ VendorLeadParams, VendorLeadResponse, LeadError }
import SparkCRM.Steps.{
  validate_and_find_vendor,
  check_business_hours,
  query_geo_bids,
  build_response
}

pipeline VendorLeadIntake[VendorLeadParams, VendorLeadResponse, LeadError] {
  step find_vendor:       validate_and_find_vendor
  step check_hours:       check_business_hours
  step find_geo_bids:     query_geo_bids
  step compute_response:  build_response
}
