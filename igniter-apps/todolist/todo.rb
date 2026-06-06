# frozen_string_literal: true

require_relative "lib/temporal_store"
require_relative "lib/repl"
require_relative "lib/ui"

def show_cli_help
  puts "\n#{TodoApp::UI::BOLD}#{TodoApp::UI::CYAN}Temporal Todo CLI Manual#{TodoApp::UI::RESET}"
  puts "Usage:"
  puts "  #{TodoApp::UI::BOLD}ruby todo.rb repl#{TodoApp::UI::RESET}                                   Start interactive REPL session (default)"
  puts "  #{TodoApp::UI::BOLD}ruby todo.rb list [--as-of <time>]#{TodoApp::UI::RESET}                     List active todos"
  puts "  #{TodoApp::UI::BOLD}ruby todo.rb add \"<title>\" [--priority <p>] [--tags <t>] [--valid-time <vt>]#{TodoApp::UI::RESET}  Add a new todo"
  puts "  #{TodoApp::UI::BOLD}ruby todo.rb complete <id> [--valid-time <vt>]#{TodoApp::UI::RESET}             Complete a todo"
  puts "  #{TodoApp::UI::BOLD}ruby todo.rb update <id> [--title <t>] [--priority <p>] [--valid-time <vt>]#{TodoApp::UI::RESET}  Update a todo"
  puts "  #{TodoApp::UI::BOLD}ruby todo.rb delete <id> [--valid-time <vt>]#{TodoApp::UI::RESET}             Soft-delete a todo"
  puts "  #{TodoApp::UI::BOLD}ruby todo.rb history <id>#{TodoApp::UI::RESET}                             Audit timeline diff tree"
  puts ""
end

def parse_args(args)
  cmd = args.shift&.downcase
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

# Helper to resolve short 8-char ID prefixes to their full UUID in CLI mode
def resolve_id(store, prefix)
  active_facts = store.active_todos
  matched = active_facts.select { |f| f.id.start_with?(prefix) }

  if matched.empty?
    all_facts = store.log.facts_for(store: "todos")
    matched = all_facts.select { |f| f.id.start_with?(prefix) }
  end

  if matched.empty?
    raise "No todo matches ID prefix '#{prefix}'!"
  elsif matched.map(&:key).uniq.size > 1
    raise "Ambiguous ID prefix '#{prefix}'! Matches multiple keys: #{matched.map { |f| f.id[0..7] }.uniq.join(', ')}"
  end

  matched.first.key
end

begin
  cmd, options = parse_args(ARGV.dup)

  if cmd.nil? || cmd == "repl"
    store = TodoApp::TemporalStore.new("todo.wal")
    begin
      TodoApp::REPL.new(store).start
    ensure
      store.close
    end
    exit
  end

  store = TodoApp::TemporalStore.new("todo.wal")

  case cmd
  when "help", "-h", "--help"
    show_cli_help
  when "list"
    as_of = options[:as_of] ? Time.parse(options[:as_of]).to_f : nil
    facts = store.active_todos(as_of: as_of)
    TodoApp::UI.print_table(facts)
  when "add"
    title = options[:positional]&.first
    raise "Missing todo title! Format: ruby todo.rb add \"<title>\"" if title.nil? || title.empty?

    priority = options[:priority] || "medium"
    tags = options[:tags] ? options[:tags].split(",") : []
    vt = options[:valid_time] ? Time.parse(options[:valid_time]).to_f : nil

    fact = store.add_todo(title, priority: priority, tags: tags, valid_time: vt)
    puts "#{TodoApp::UI::GREEN}✔ Fact Added Durable WAL!#{TodoApp::UI::RESET} #{TodoApp::UI::GRAY}(id: #{fact.id})#{TodoApp::UI::RESET}"
  when "complete"
    id_prefix = options[:positional]&.first
    raise "Missing todo ID! Format: ruby todo.rb complete <id>" if id_prefix.nil? || id_prefix.empty?

    id = resolve_id(store, id_prefix)
    vt = options[:valid_time] ? Time.parse(options[:valid_time]).to_f : nil

    fact = store.complete_todo(id, valid_time: vt)
    puts "#{TodoApp::UI::GREEN}✔ Fact Updated Durable WAL (Completed)!#{TodoApp::UI::RESET} #{TodoApp::UI::GRAY}(id: #{fact.id})#{TodoApp::UI::RESET}"
  when "update"
    id_prefix = options[:positional]&.first
    raise "Missing todo ID! Format: ruby todo.rb update <id>" if id_prefix.nil? || id_prefix.empty?

    id = resolve_id(store, id_prefix)
    title = options[:title]
    priority = options[:priority]
    tags = options[:tags] ? options[:tags].split(",") : nil
    vt = options[:valid_time] ? Time.parse(options[:valid_time]).to_f : nil

    fact = store.update_todo(id, title: title, priority: priority, tags: tags, valid_time: vt)
    puts "#{TodoApp::UI::GREEN}✔ Fact Updated Durable WAL (Fields)!#{TodoApp::UI::RESET} #{TodoApp::UI::GRAY}(id: #{fact.id})#{TodoApp::UI::RESET}"
  when "delete"
    id_prefix = options[:positional]&.first
    raise "Missing todo ID! Format: ruby todo.rb delete <id>" if id_prefix.nil? || id_prefix.empty?

    id = resolve_id(store, id_prefix)
    vt = options[:valid_time] ? Time.parse(options[:valid_time]).to_f : nil

    fact = store.delete_todo(id, valid_time: vt)
    puts "#{TodoApp::UI::GREEN}✔ Fact Soft-Deleted Durable WAL!#{TodoApp::UI::RESET} #{TodoApp::UI::GRAY}(id: #{fact.id})#{TodoApp::UI::RESET}"
  when "history"
    id_prefix = options[:positional]&.first
    raise "Missing todo ID! Format: ruby todo.rb history <id>" if id_prefix.nil? || id_prefix.empty?

    id = resolve_id(store, id_prefix)
    facts = store.history(id)
    TodoApp::UI.print_history(facts)
  else
    puts "#{TodoApp::UI::RED}Unknown command: '#{cmd}'.#{TodoApp::UI::RESET}"
    show_cli_help
    exit 1
  end

rescue => e
  puts "#{TodoApp::UI::RED}Error: #{e.message}#{TodoApp::UI::RESET}"
  exit 1
ensure
  store&.close
end
