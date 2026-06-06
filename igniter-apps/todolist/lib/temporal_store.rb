# frozen_string_literal: true

require "securerandom"

# Load Playground compiled Rust extension
$LOAD_PATH.unshift(File.expand_path("../../../igniter-tbackend/target/release", __dir__))
begin
  require "igniter_tbackend_playground"
rescue LoadError => e
  raise "Failed to load Compiled Rust tbackend extension! Have you run cargo build? Error: #{e.message}"
end

# Setup Playground Ruby wrappers for native FFI bindings
module Igniter
  module TBackendPlayground
    class Fact
      def self.build(store:, key:, value:, causation: nil, valid_time: nil, term: nil, schema_version: 1)
        vt = valid_time.nil? ? (term ? term.to_f : nil) : valid_time.to_f
        _native_build(
          store.to_s,
          key.to_s,
          value,
          causation,
          vt,
          schema_version.to_i
        )
      end

      alias_method :_native_value, :value
      def value = _native_value
    end

    class FactLog
      def append(fact)
        _native_append(fact)
        fact
      end

      def latest_for(store:, key:, as_of: nil)
        latest_for_native(store.to_s, key.to_s, as_of&.to_f)
      end

      def facts_for(store:, key: nil, since: nil, as_of: nil)
        facts_for_native(store.to_s, key&.to_s, since&.to_f, as_of&.to_f)
      end

      def query_scope(store:, filters:, as_of: nil)
        query_scope_native(store.to_s, filters, as_of&.to_f)
      end
    end
  end
end

module TodoApp
  class TemporalStore
    attr_reader :log, :wal

    def initialize(wal_path = "todo.wal")
      @log = Igniter::TBackendPlayground::FactLog.new
      @wal = Igniter::TBackendPlayground::FileBackend.new(wal_path)

      # Replay the Write-Ahead-Log on startup to fully restore in-memory state
      @wal.replay.each do |fact|
        @log.replay(fact)
      end
    end

    def close
      @wal.close rescue nil
    end

    # --- Bitemporal Domain Actions ---

    # Add a new todo with optional backdated valid_time
    def add_todo(title, priority: "medium", tags: [], valid_time: nil)
      id = SecureRandom.uuid
      value = {
        title: title,
        status: "pending",
        priority: priority.to_s,
        tags: Array(tags).map(&:to_s),
        deleted: false
      }

      fact = Igniter::TBackendPlayground::Fact.build(
        store: "todos",
        key: id,
        value: value,
        valid_time: valid_time,
        schema_version: 1
      )

      @log.append(fact)
      @wal.write_fact(fact)
      fact
    end

    # Complete an existing todo (soft status change) with optional backdated valid_time
    def complete_todo(id, valid_time: nil)
      previous = @log.latest_for(store: "todos", key: id)
      raise "Todo not found!" unless previous && !previous.value[:deleted]

      value = previous.value.dup
      value[:status] = "completed"

      fact = Igniter::TBackendPlayground::Fact.build(
        store: "todos",
        key: id,
        value: value,
        causation: previous.id,
        valid_time: valid_time,
        schema_version: 1
      )

      @log.append(fact)
      @wal.write_fact(fact)
      fact
    end

    # Update todo fields (title, priority, tags)
    def update_todo(id, title: nil, priority: nil, tags: nil, valid_time: nil)
      previous = @log.latest_for(store: "todos", key: id)
      raise "Todo not found!" unless previous && !previous.value[:deleted]

      value = previous.value.dup
      value[:title] = title if title
      value[:priority] = priority.to_s if priority
      value[:tags] = Array(tags).map(&:to_s) if tags

      fact = Igniter::TBackendPlayground::Fact.build(
        store: "todos",
        key: id,
        value: value,
        causation: previous.id,
        valid_time: valid_time,
        schema_version: 1
      )

      @log.append(fact)
      @wal.write_fact(fact)
      fact
    end

    # Soft-delete a todo from active scopes
    def delete_todo(id, valid_time: nil)
      previous = @log.latest_for(store: "todos", key: id)
      raise "Todo not found!" unless previous && !previous.value[:deleted]

      value = previous.value.dup
      value[:deleted] = true

      fact = Igniter::TBackendPlayground::Fact.build(
        store: "todos",
        key: id,
        value: value,
        causation: previous.id,
        valid_time: valid_time,
        schema_version: 1
      )

      @log.append(fact)
      @wal.write_fact(fact)
      fact
    end

    # --- Bitemporal Query Operations ---

    # Fetches active (non-deleted) todos at a specific transaction-time coordinate
    def active_todos(as_of: nil)
      # We query the FactLog via query_scope
      @log.query_scope(store: "todos", filters: { deleted: false }, as_of: as_of)
    end

    # Retrieves full chronological commit timeline of a specific todo item
    def history(id)
      @log.facts_for(store: "todos", key: id)
    end
  end
end
