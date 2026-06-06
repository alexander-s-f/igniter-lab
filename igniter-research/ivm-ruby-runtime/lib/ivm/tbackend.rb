# frozen_string_literal: true

require "digest"
require "json"

module IVM
  # Abstract representation of a Pluggable Temporal Database Backend (TBackend).
  # Serves temporal data for LOAD_AS_OF execution instructions.
  class TBackend
    # Abstract read_as_of interface.
    # Must return a tuple: [result_hash, provenance_observation_hash]
    def read_as_of(store_name, as_of)
      raise NotImplementedError, "#{self.class} has not implemented read_as_of"
    end
  end

  # Ephemeral, in-memory valid-time historical data store.
  # Suitable for test environments and proof-of-concept sandboxes.
  class MemoryHistoryBackend < TBackend
    attr_reader :store

    def initialize
      super()
      # Structure: store_name -> Array of { valid_time: DateTime, value: Hash }
      @store = {}
    end

    # Insert a historical record into a specific store.
    #
    # store_name - String identifier (e.g. "technician_jobs")
    # valid_time - String representing valid time (e.g., "2026-05-01T00:00:00Z")
    # value      - Any serializable value hash (e.g. { "count" => 7 })
    def write_history(store_name, valid_time, value)
      @store[store_name] ||= []
      @store[store_name] << {
        valid_time: Time.parse(valid_time),
        value: value
      }
      # Maintain sorted records by valid_time ascending
      @store[store_name].sort_by! { |r| r[:valid_time] }
    end

    # Retrieve a historical value as of a specific valid time.
    # Matches the closest record whose valid_time <= as_of.
    #
    # Returns [result_hash, provenance_observation_hash]
    def read_as_of(store_name, as_of)
      records = @store[store_name]
      query_time = Time.parse(as_of)

      # Match closest historical record where valid_time <= query_time
      match = if records
                records.reverse.find { |r| r[:valid_time] <= query_time }
              else
                nil
              end

      result = if match
                 { "kind" => "some", "value" => match[:value] }
               else
                 { "kind" => "none" }
               end

      # Construct observation trace
      prov_id = "obs/prov/#{Digest::SHA256.hexdigest("#{store_name}-#{as_of}-#{result.inspect}")[0, 16]}"
      prov_obs = {
        "observation_id" => prov_id,
        "kind" => "provenance_observation",
        "store" => store_name,
        "query_as_of" => as_of,
        "matched_valid_time" => match ? match[:valid_time].to_s : nil,
        "matched_value" => match ? match[:value] : nil
      }

      [result, prov_obs]
    end
  end
end
