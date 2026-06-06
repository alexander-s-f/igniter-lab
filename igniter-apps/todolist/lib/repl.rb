# frozen_string_literal: true

require "shellwords"
require "time"
require_relative "ui"

module TodoApp
  class REPL
    def initialize(store)
      @store = store
      @as_of = nil # nil means present time
    end

    def start
      UI.header("TEMPORAL TODO REPL v1.0")
      puts "#{UI::GRAY}Type 'help' to list available commands. Type 'exit' to quit.#{UI::RESET}"
      puts "#{UI::GRAY}Durable Bitemporal Store is active and replayed successfully.#{UI::RESET}\n"

      loop do
        # Dynamically change prompt to show bitemporal state
        prompt = if @as_of
                   t_str = Time.at(@as_of).strftime("%Y-%m-%d %H:%M:%S")
                   "#{UI::BOLD}#{UI::YELLOW}(as_of: #{t_str}) #{UI::CYAN}todo> #{UI::RESET}"
                 else
                   "#{UI::BOLD}#{UI::CYAN}todo> #{UI::RESET}"
                 end

        print prompt
        input = gets
        break if input.nil? # EOF

        input = input.strip
        next if input.empty?

        begin
          cmd, options = parse_line(input)
          case cmd
          when "exit", "quit"
            puts "\n#{UI::GRAY}Exiting. Temporal database closed gracefully.#{UI::RESET}"
            break
          when "help"
            show_help
          when "list"
            list_todos
          when "add"
            add_todo(options)
          when "complete"
            complete_todo(options)
          when "update"
            update_todo(options)
          when "delete"
            delete_todo(options)
          when "history"
            todo_history(options)
          when "time-travel"
            time_travel(options)
          else
            puts "#{UI::RED}Unknown command: '#{cmd}'. Type 'help' for instructions.#{UI::RESET}"
          end
        rescue => e
          puts "#{UI::RED}Error: #{e.message}#{UI::RESET}"
        end
      end
    end

    private

    def parse_line(input_str)
      args = Shellwords.split(input_str)
      cmd = args.shift.downcase
      options = {}

      loop do
        arg = args.shift
        break unless arg

        if arg.start_with?("--")
          key = arg[2..].gsub("-", "_").to_sym
          val = args.shift
          raise "Missing value for option #{arg}" unless val
          options[key] = val
        else
          (options[:positional] ||= []) << arg
        end
      end

      [cmd, options]
    end

    def show_help
      puts "\n#{UI::BOLD}#{UI::CYAN}Available Bitemporal Commands:#{UI::RESET}"
      puts "  #{UI::BOLD}list#{UI::RESET}                                        List active todos (respects time-travel)"
      puts "  #{UI::BOLD}add#{UI::RESET} \"<title>\" [--priority <p>] [--tags <t>]      Add a todo (optional --valid-time)"
      puts "  #{UI::BOLD}complete#{UI::RESET} <id> [--valid-time <time>]            Complete a todo (optional backdated)"
      puts "  #{UI::BOLD}update#{UI::RESET} <id> [--title <t>] [--priority <p>]      Update todo fields"
      puts "  #{UI::BOLD}delete#{UI::RESET} <id> [--valid-time <time>]              Soft-delete a todo"
      puts "  #{UI::BOLD}history#{UI::RESET} <id>                                 Audit bitemporal commit timeline tree"
      puts "  #{UI::BOLD}time-travel#{UI::RESET} \"<timestamp>\" | reset              Step back in time globally (or return to present)"
      puts "  #{UI::BOLD}help#{UI::RESET}                                        Show this command manual"
      puts "  #{UI::BOLD}exit#{UI::RESET} / #{UI::BOLD}quit#{UI::RESET}                               Exit the REPL session\n\n"
    end

    def list_todos
      facts = @store.active_todos(as_of: @as_of)
      # Resolve IDs if short prefix matches (only for display, print_table handles it)
      UI.print_table(facts)
    end

    def add_todo(options)
      title = options[:positional]&.first
      raise "Missing todo title! Format: add \"<title>\"" if title.nil? || title.empty?

      priority = options[:priority] || "medium"
      tags = options[:tags] ? options[:tags].split(",") : []
      vt = options[:valid_time] ? Time.parse(options[:valid_time]).to_f : nil

      fact = @store.add_todo(title, priority: priority, tags: tags, valid_time: vt)
      puts "#{UI::GREEN}✔ Fact Added Durable WAL!#{UI::RESET} #{UI::GRAY}(id: #{fact.id})#{UI::RESET}"
    end

    def complete_todo(options)
      id_prefix = options[:positional]&.first
      raise "Missing todo ID! Format: complete <id>" if id_prefix.nil? || id_prefix.empty?

      id = resolve_id(id_prefix)
      vt = options[:valid_time] ? Time.parse(options[:valid_time]).to_f : nil

      fact = @store.complete_todo(id, valid_time: vt)
      puts "#{UI::GREEN}✔ Fact Updated Durable WAL (Completed)!#{UI::RESET} #{UI::GRAY}(id: #{fact.id})#{UI::RESET}"
    end

    def update_todo(options)
      id_prefix = options[:positional]&.first
      raise "Missing todo ID! Format: update <id>" if id_prefix.nil? || id_prefix.empty?

      id = resolve_id(id_prefix)
      title = options[:title]
      priority = options[:priority]
      tags = options[:tags] ? options[:tags].split(",") : nil
      vt = options[:valid_time] ? Time.parse(options[:valid_time]).to_f : nil

      fact = @store.update_todo(id, title: title, priority: priority, tags: tags, valid_time: vt)
      puts "#{UI::GREEN}✔ Fact Updated Durable WAL (Fields)!#{UI::RESET} #{UI::GRAY}(id: #{fact.id})#{UI::RESET}"
    end

    def delete_todo(options)
      id_prefix = options[:positional]&.first
      raise "Missing todo ID! Format: delete <id>" if id_prefix.nil? || id_prefix.empty?

      id = resolve_id(id_prefix)
      vt = options[:valid_time] ? Time.parse(options[:valid_time]).to_f : nil

      fact = @store.delete_todo(id, valid_time: vt)
      puts "#{UI::GREEN}✔ Fact Soft-Deleted Durable WAL!#{UI::RESET} #{UI::GRAY}(id: #{fact.id})#{UI::RESET}"
    end

    def todo_history(options)
      id_prefix = options[:positional]&.first
      raise "Missing todo ID! Format: history <id>" if id_prefix.nil? || id_prefix.empty?

      id = resolve_id(id_prefix)
      facts = @store.history(id)
      UI.print_history(facts)
    end

    def time_travel(options)
      arg = options[:positional]&.first
      raise "Missing timestamp! Format: time-travel \"YYYY-MM-DD HH:MM:SS\" or reset" if arg.nil? || arg.empty?

      if arg.downcase == "reset" || arg.downcase == "now"
        @as_of = nil
        puts "#{UI::GREEN}Returned to present time (Chronological).#{UI::RESET}"
      else
        begin
          @as_of = Time.parse(arg).to_f
          puts "#{UI::YELLOW}Time-traveled globally. Active todo views now projected as of #{Time.at(@as_of).strftime('%Y-%m-%d %H:%M:%S')}.#{UI::RESET}"
        rescue => e
          raise "Invalid time format! Please use YYYY-MM-DD HH:MM:SS or similar."
        end
      end
    end

    # Helper to resolve short 8-char ID prefixes to their full UUID
    def resolve_id(prefix)
      # Get all keys currently active or in history to resolve prefix
      # Scan active todos first
      active_facts = @store.active_todos
      matched = active_facts.select { |f| f.id.start_with?(prefix) }

      if matched.empty?
        # If not active, scan all store facts across history
        # We can iterate over all sharded facts by querying without key
        all_facts = @store.log.facts_for(store: "todos")
        matched = all_facts.select { |f| f.id.start_with?(prefix) }
      end

      if matched.empty?
        raise "No todo matches ID prefix '#{prefix}'!"
      elsif matched.map(&:key).uniq.size > 1
        raise "Ambiguous ID prefix '#{prefix}'! Matches multiple keys: #{matched.map { |f| f.id[0..7] }.uniq.join(', ')}"
      end

      matched.first.key
    end
  end
end
