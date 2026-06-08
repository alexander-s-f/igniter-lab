-- liveness_emitter_pipeline_depth.ig
-- LAB-COMPILER-LIVENESS-P4 calibration fixture: emitter.build_pipeline.max_depth
--
-- Exercises the emitter build_pipeline recursive descent by chaining 9 filter
-- operations inside a sum terminal that is itself inside an if_expr branch.
-- build_pipeline is only called when a pipeline terminal (sum/count/fold/etc.)
-- is processed via semantic_expr, which happens inside if_expr branches.
--
-- Each filter layer in build_pipeline adds 1 depth; the terminal collection
-- (leads) itself is the last level.  Formula:
--   N nested filter/map inside a terminal op → depth = N + 1
--
-- Expected: emitter.build_pipeline.max_depth = 10, status = ok

module Lang.Lab.LivenessEmitterPipelineDepth

type Lead {
  lead_id:    Integer,
  bid_amount: Integer,
  bid_decimal: Decimal[2]
}

-- 9 nested filter calls inside sum (inside if_expr) → build_pipeline depth = 10
contract DeepPipeline {
  input leads:     Collection[Lead]
  input threshold: Integer

  compute result =
    if count(leads) > 0 {
      sum(
        filter(
          filter(
            filter(
              filter(
                filter(
                  filter(
                    filter(
                      filter(
                        filter(leads, l -> l.bid_amount > 0),
                        l -> l.bid_amount > 1),
                      l -> l.bid_amount > 2),
                    l -> l.bid_amount > 3),
                  l -> l.bid_amount > 4),
                l -> l.bid_amount > 5),
              l -> l.bid_amount > 6),
            l -> l.bid_amount > 7),
          l -> l.bid_amount > 8),
        :bid_decimal)
    } else {
      sum(leads, :bid_decimal)
    }

  output result: Decimal[2]
}
