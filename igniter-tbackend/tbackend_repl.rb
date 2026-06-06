# frozen_string_literal: true

require "json"
require "socket"
require "zlib"
require "time"
require "securerandom"
require "shellwords"
require "digest"
require "readline"

Dir.chdir(__dir__)

CONFIG_FILE = "tbackend.config.json"

# ANSI text styling matching our bitemporal UI conventions
module Style
  RESET   = "\e[0m"
  BOLD    = "\e[1m"
  GRAY    = "\e[90m"
  RED     = "\e[31m"
  GREEN   = "\e[32m"
  YELLOW  = "\e[33m"
  BLUE    = "\e[34m"
  MAGENTA = "\e[35m"
  CYAN    = "\e[36m"
  WHITE   = "\e[37m"
end

class TBackendClient
  def initialize(host, port)
    @socket = TCPSocket.new(host, port)
    @socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, true)
  end

  def ping
    send_req(op: "ping")[:pong] == true
  end

  def send_req(req)
    body = JSON.generate(req).b
    frame = [body.bytesize].pack("N") << body << [Zlib.crc32(body)].pack("N")
    @socket.write(frame)
    
    header = @socket.read(4)
    return { ok: false, error: "EOF" } unless header && header.bytesize == 4
    
    len = header.unpack1("N")
    resp_body = @socket.read(len)
    return { ok: false, error: "Truncated body" } unless resp_body && resp_body.bytesize == len
    
    crc_bytes = @socket.read(4)
    return { ok: false, error: "Truncated CRC" } unless crc_bytes && crc_bytes.bytesize == 4
    
    raise "CRC mismatch" unless Zlib.crc32(resp_body) == crc_bytes.unpack1("N")
    
    JSON.parse(resp_body, symbolize_names: true)
  end

  def close
    send_req(op: "close") rescue nil
    @socket.close rescue nil
  end
end

class AdministrativeREPL
  def initialize(host, port)
    @host = host
    @port = port
    @as_of = nil
    @client = nil
    @stores_cache = []
    connect_client
    setup_readline_completion
  end

  def start
    puts "\n#{Style::BOLD}#{Style::CYAN}┌──────────────────────────────────────────────────────────────┐#{Style::RESET}"
    puts "#{Style::BOLD}#{Style::CYAN}│              #{Style::MAGENTA}TBACKEND ADMINISTRATIVE SHELL v1.0#{Style::CYAN}              │#{Style::RESET}"
    puts "#{Style::BOLD}#{Style::CYAN}└──────────────────────────────────────────────────────────────┘#{Style::RESET}"
    puts "#{Style::GRAY}Connecting to TBackend daemon at #{@host}:#{@port}...#{Style::RESET}"
    
    if ping_ok?
      puts "#{Style::GREEN}✔ Handshake successful! TBackend Server is Online.#{Style::RESET}"
      refresh_stores_cache rescue nil
    else
      puts "#{Style::RED}⚠ Warning: TBackend Server offline at #{@host}:#{@port}. Connect live later.#{Style::RESET}"
    end
    
    puts "#{Style::GRAY}Type 'help' for instructions. Type 'exit' or 'quit' to close.#{Style::RESET}\n\n"

    loop do
      prompt = if @as_of
                 t_str = Time.at(@as_of).strftime("%Y-%m-%d %H:%M:%S")
                 "#{Style::BOLD}#{Style::YELLOW}(as_of: #{t_str}) #{Style::CYAN}tbackend> #{Style::RESET}"
               else
                 "#{Style::BOLD}#{Style::CYAN}tbackend> #{Style::RESET}"
               end

      # Use Readline instead of gets for arrows history + Tab completion!
      input = Readline.readline(prompt, true)
      break if input.nil? # EOF

      input = input.strip
      next if input.empty?

      begin
        cmd, options = parse_line(input)
        case cmd
        when "exit", "quit"
          puts "#{Style::GRAY}Closing socket session. Exiting.#{Style::RESET}"
          break
        when "help"
          show_help
        when "ping"
          run_ping
        when "put", "set", "write"
          run_put(options)
        when "get", "read", "latest"
          run_get(options)
        when "list", "query"
          run_list(options)
        when "history", "timeline"
          run_history(options)
        when "time-travel"
          run_time_travel(options)
        when "telemetry", "status"
          run_telemetry
        when "size"
          run_size
        else
          puts "#{Style::RED}Unknown command: '#{cmd}'. Type 'help' for command manual.#{Style::RESET}"
        end
      rescue => e
        puts "#{Style::RED}Error: #{e.message}#{Style::RESET}"
      end
    end
  end

  private

  def connect_client
    @client = TBackendClient.new(@host, @port) rescue nil
  end

  def ensure_connection
    return true if @client
    connect_client
    if @client.nil?
      raise "TBackend daemon offline at #{@host}:#{@port}! Please start it first: ruby tbackend_service.rb start"
    end
    true
  end

  def ping_ok?
    return false unless @client
    @client.ping rescue false
  end

  def refresh_stores_cache
    return unless @client
    res = @client.send_req(op: "stores")
    if res[:ok] && res[:stores]
      @stores_cache = res[:stores]
    end
  end

  def setup_readline_completion
    commands = ["ping", "put", "set", "write", "get", "read", "latest", "list", "query", "history", "timeline", "time-travel", "telemetry", "status", "size", "help", "exit", "quit"]
    
    Readline.completion_proc = proc do |s|
      line = Readline.line_buffer.to_s.strip
      words = Shellwords.split(line) rescue [line]

      if line.start_with?(s) && words.size <= 1
        commands.select { |c| c.start_with?(s) }
      else
        first_word = words.first&.downcase
        if ["put", "set", "write", "get", "read", "latest", "list", "query", "history", "timeline"].include?(first_word)
          @stores_cache.select { |st| st.start_with?(s) }
        else
          []
        end
      end
    end

    Readline.completion_append_character = " "
  end

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
    puts "\n#{Style::BOLD}#{Style::CYAN}TBackend Administrative Commands:#{Style::RESET}"
    puts "  #{Style::BOLD}ping#{Style::RESET}                                        Test wire latency"
    puts "  #{Style::BOLD}put#{Style::RESET} <store> <key> '<json_val>' [--valid-time <vt>] Appends/Writes a bitemporal fact"
    puts "  #{Style::BOLD}get#{Style::RESET} <store> <key>                              Gets latest fact (respects time-travel)"
    puts "  #{Style::BOLD}list#{Style::RESET} <store> ['<filters_json>']                Queries/Lists active facts in a store"
    puts "  #{Style::BOLD}history#{Style::RESET} <store> <key>                          Audits chronological revision timeline diffs"
    puts "  #{Style::BOLD}time-travel#{Style::RESET} \"<timestamp>\" | reset              Steps back in transaction-time globally"
    puts "  #{Style::BOLD}telemetry#{Style::RESET} / #{Style::BOLD}status#{Style::RESET}                      Queries Rust live diagnostic counters"
    puts "  #{Style::BOLD}size#{Style::RESET}                                        Outputs total database fact log count"
    puts "  #{Style::BOLD}help#{Style::RESET}                                        Show this manual"
    puts "  #{Style::BOLD}exit#{Style::RESET} / #{Style::BOLD}quit#{Style::RESET}                               Disconnect and quit#{Style::RESET}\n\n"
  end

  def run_ping
    ensure_connection
    t_start = Time.now
    if @client.ping
      elapsed = ((Time.now - t_start) * 1000).round(2)
      puts "#{Style::GREEN}✔ Pong! Network wire latency: #{elapsed} ms#{Style::RESET}"
    else
      puts "#{Style::RED}✘ Ping failed! Connection timeout.#{Style::RESET}"
    end
  end

  def sort_keys(val)
    if val.is_a?(Hash)
      val.map { |k, v| [k.to_s, sort_keys(v)] }.sort.to_h
    elsif val.is_a?(Array)
      val.map { |item| sort_keys(item) }
    else
      val
    end
  end

  def run_put(options)
    ensure_connection
    pos = options[:positional] || []
    store = pos[0]
    key = pos[1]
    val_json_str = pos[2]

    raise "Usage: put <store> <key> '<json_value>' [--valid-time <vt>]" if store.nil? || key.nil? || val_json_str.nil?

    begin
      value = JSON.parse(val_json_str)
    rescue JSON::ParserError => e
      raise "Invalid JSON payload: #{e.message}"
    end

    vt = options[:valid_time] ? Time.parse(options[:valid_time]).to_f : nil

    # Query latest to establish causation parent revision ID link
    prev = @client.send_req(op: "latest_for", store: store, key: key)[:fact]
    causation = prev ? prev[:id] : nil

    # Compute stable cryptographic hex hash
    sorted_val = sort_keys(value)
    hash_payload = JSON.generate(sorted_val)
    value_hash = Digest::SHA256.hexdigest(hash_payload)

    fact = {
      id: SecureRandom.uuid,
      store: store,
      key: key,
      value: value,
      value_hash: value_hash,
      causation: causation,
      transaction_time: Time.now.to_f,
      valid_time: vt,
      schema_version: 1,
      producer: nil,
      derivation: nil
    }

    res = @client.send_req(op: "write_fact", fact: fact)
    if res[:ok]
      puts "#{Style::GREEN}✔ Fact committed to durable WAL over TCP!#{Style::RESET} #{Style::GRAY}(id: #{fact[:id]}, hash: #{value_hash[0..11]}...)#{Style::RESET}"
      refresh_stores_cache rescue nil
    else
      puts "#{Style::RED}✘ Failed to commit fact: #{res[:error]}#{Style::RESET}"
    end
  end

  def run_get(options)
    ensure_connection
    pos = options[:positional] || []
    store = pos[0]
    key = pos[1]

    raise "Usage: get <store> <key>" if store.nil? || key.nil?

    res = @client.send_req(op: "latest_for", store: store, key: key, as_of: @as_of)
    if res[:ok] && res[:fact]
      fact = res[:fact]
      print_fact_table([fact])
    else
      puts "#{Style::YELLOW}No fact found for key '#{key}' in store '#{store}'.#{Style::RESET}"
    end
  end

  def run_list(options)
    ensure_connection
    pos = options[:positional] || []
    store = pos[0]
    filter_json_str = pos[1]

    raise "Usage: list <store> ['<filters_json>']" if store.nil?

    filters = {}
    if filter_json_str
      begin
        filters = JSON.parse(filter_json_str)
      rescue JSON::ParserError => e
        raise "Invalid filter JSON: #{e.message}"
      end
    end

    # Query matching scope
    res = @client.send_req(op: "query_scope", store: store, filters: filters, as_of: @as_of)
    if res[:ok] && res[:facts] && !res[:facts].empty?
      print_fact_table(res[:facts])
    else
      puts "#{Style::YELLOW}No matching facts found.#{Style::RESET}"
    end
  end

  def run_history(options)
    ensure_connection
    pos = options[:positional] || []
    store = pos[0]
    key = pos[1]

    raise "Usage: history <store> <key>" if store.nil? || key.nil?

    res = @client.send_req(op: "facts_for", store: store, key: key)
    if res[:ok] && res[:facts] && !res[:facts].empty?
      print_history_tree(res[:facts])
    else
      puts "#{Style::YELLOW}No bitemporal revision history found.#{Style::RESET}"
    end
  end

  def run_time_travel(options)
    arg = options[:positional]&.first
    raise "Usage: time-travel \"YYYY-MM-DD HH:MM:SS\" | reset" if arg.nil? || arg.empty?

    if arg.downcase == "reset" || arg.downcase == "now"
      @as_of = nil
      puts "#{Style::GREEN}Returned to present timeline.#{Style::RESET}"
    else
      begin
        @as_of = Time.parse(arg).to_f
        puts "#{Style::YELLOW}Travelled globally in transaction-time. Admin views now projected as of #{Time.at(@as_of).strftime('%Y-%m-%d %H:%M:%S')}.#{Style::RESET}"
      rescue
        raise "Invalid timestamp format. Please use YYYY-MM-DD HH:MM:SS."
      end
    end
  end

  def run_telemetry
    ensure_connection
    metrics = @client.send_req(op: "metrics")
    if metrics
      print_telemetry_dashboard(metrics)
    else
      puts "#{Style::RED}Could not fetch metrics!#{Style::RESET}"
    end
  end

  def run_size
    ensure_connection
    res = @client.send_req(op: "size")
    if res[:ok]
      puts "#{Style::GREEN}Database Size: #{Style::BOLD}#{res[:size]}#{Style::RESET} bitemporal facts registered in sharded logs."
    else
      puts "#{Style::RED}Failed: #{res[:error]}#{Style::RESET}"
    end
  end

  # Rendering helpers
  def print_fact_table(facts)
    puts "#{Style::BOLD}#{Style::CYAN}┌──────────┬────────────┬────────────────────────────┬─────────────────────────────┬──────────────────┐#{Style::RESET}"
    puts "#{Style::BOLD}#{Style::CYAN}│ ID (8)   │ KEY        │ VALUE HASH                 │ TRANSACTION TIME            │ VALID TIME       │#{Style::RESET}"
    puts "#{Style::BOLD}#{Style::CYAN}├──────────┼────────────┼────────────────────────────┼─────────────────────────────┼──────────────────┤#{Style::RESET}"
    
    facts.each do |fact|
      id = fact[:id][0..7]
      key = fact[:key].to_s[0..9].ljust(10)
      hash = fact[:value_hash].to_s[0..24].ljust(26)
      tt = Time.at(fact[:transaction_time]).strftime("%Y-%m-%d %H:%M:%S")
      vt = fact[:valid_time] ? Time.at(fact[:valid_time]).strftime("%Y-%m-%d %H:%M") : "Present"
      vt = vt.ljust(16)

      printf("#{Style::CYAN}│#{Style::RESET} %-8s #{Style::CYAN}│#{Style::RESET} %-10s #{Style::CYAN}│#{Style::RESET} %-26s #{Style::CYAN}│#{Style::RESET} %-27s #{Style::CYAN}│#{Style::RESET} %-16s #{Style::CYAN}│#{Style::RESET}\n",
             id, key, hash, tt, vt)
      
      # Print indented JSON payload
      puts "#{Style::CYAN}│#{Style::RESET}          #{Style::BOLD}VALUE: #{Style::RESET}#{Style::GRAY}#{fact[:value].to_json}#{Style::RESET}".ljust(102) + "#{Style::CYAN}│#{Style::RESET}"
      puts "#{Style::CYAN}├──────────┴────────────┴────────────────────────────┴─────────────────────────────┴──────────────────┤#{Style::RESET}" unless fact == facts.last
    end
    
    puts "#{Style::BOLD}#{Style::CYAN}└──────────┴────────────┴────────────────────────────┴─────────────────────────────┴──────────────────┘#{Style::RESET}\n"
  end

  def print_history_tree(facts)
    first = facts.first
    puts "\n#{Style::BOLD}#{Style::MAGENTA}History Lineage Diff Tree: #{first[:store]} / #{first[:key]}#{Style::RESET}"
    puts "#{Style::GRAY}Total registered revisions: #{facts.size}#{Style::RESET}\n"

    facts.each_with_index do |fact, idx|
      if idx > 0
        puts "  #{Style::CYAN}│#{Style::RESET}"
        puts "  #{Style::CYAN}▼ (Causal Revision Link)#{Style::RESET}"
      end

      puts "#{Style::BOLD}#{Style::GREEN}● [Revision ##{idx + 1}]#{Style::RESET} #{Style::GRAY}(id: #{fact[:id][0..11]}...)#{Style::RESET}"
      puts "  ├── #{Style::BOLD}Transaction Time:#{Style::RESET} #{Time.at(fact[:transaction_time]).strftime('%Y-%m-%d %H:%M:%S')}"
      
      vt_str = fact[:valid_time] ? "#{Time.at(fact[:valid_time]).strftime('%Y-%m-%d %H:%M:%S')} #{Style::BOLD}#{Style::YELLOW}(Backdated!)#{Style::RESET}" : "#{Style::GRAY}Present (Chronological)#{Style::RESET}"
      puts "  ├── #{Style::BOLD}Valid Time:      #{Style::RESET}#{vt_str}"
      
      cause_str = fact[:causation] ? "#{fact[:causation][0..11]}..." : "#{Style::GRAY}(Root Fact - Genesis)#{Style::RESET}"
      puts "  ├── #{Style::BOLD}Causation Link:  #{Style::RESET}#{cause_str}"
      
      if idx == 0
        # Genesis starting state
        puts "  └── #{Style::BOLD}Initial State:   #{Style::RESET}"
        fact[:value].each do |k, v|
          puts "      #{Style::GRAY}#{k}:#{Style::RESET} #{v.inspect}"
        end
      else
        # Print differences compared to prior revision
        prev = facts[idx - 1]
        diffs = []
        
        fact[:value].each do |k, v|
          if prev[:value][k] != v
            diffs << "      #{Style::BOLD}#{Style::YELLOW}[~] #{k}:#{Style::RESET} #{prev[:value][k].inspect} #{Style::CYAN}➔#{Style::RESET} #{v.inspect}"
          end
        end

        # Find deleted fields in new revision
        prev[:value].each do |k, v|
          unless fact[:value].key?(k)
            diffs << "      #{Style::BOLD}#{Style::RED}[-] #{k}:#{Style::RESET} #{v.inspect} #{Style::RED}(Deleted)#{Style::RESET}"
          end
        end

        # Find newly added fields in new revision
        fact[:value].each do |k, v|
          unless prev[:value].key?(k)
            diffs << "      #{Style::BOLD}#{Style::GREEN}[+] #{k}:#{Style::RESET} #{v.inspect} #{Style::GREEN}(Added)#{Style::RESET}"
          end
        end
        
        puts "  └── #{Style::BOLD}State Changes:   #{Style::RESET}"
        if diffs.empty?
          puts "      #{Style::GRAY}(No payload changes - metadata update)#{Style::RESET}"
        else
          diffs.each { |d| puts d }
        end
      end
    end
    puts ""
  end

  def format_bytes(bytes)
    if bytes >= 1024 * 1024
      "#{(bytes.to_f / (1024 * 1024)).round(2)} MB"
    elsif bytes >= 1024
      "#{(bytes.to_f / 1024).round(2)} KB"
    else
      "#{bytes} B"
    end
  end

  def print_telemetry_dashboard(metrics)
    puts "\n#{Style::BOLD}#{Style::CYAN}┌──────────────────────────────────────────────────────────────┐#{Style::RESET}"
    puts "#{Style::BOLD}#{Style::CYAN}│                  #{Style::MAGENTA}TBACKEND TELEMETRY DASHBOARD#{Style::CYAN}                │#{Style::RESET}"
    puts "#{Style::BOLD}#{Style::CYAN}├──────────────────────────────────────────────────────────────┤#{Style::RESET}"
    puts "#{Style::BOLD}#{Style::CYAN}│#{Style::RESET} Status:        #{Style::GREEN}🟢 Active / Online#{Style::RESET}                            #{Style::BOLD}#{Style::CYAN}│#{Style::RESET}"
    puts "#{Style::BOLD}#{Style::CYAN}│#{Style::RESET} Host/Port:     #{Style::WHITE}#{@host}:#{@port}#{Style::RESET}".ljust(69) + "#{Style::BOLD}#{Style::CYAN}│#{Style::RESET}"
    puts "#{Style::BOLD}#{Style::CYAN}│#{Style::RESET} Connections:   #{Style::BOLD}#{Style::BLUE}#{metrics[:active_connections]}#{Style::RESET} active".ljust(69) + "#{Style::BOLD}#{Style::CYAN}│#{Style::RESET}"
    puts "#{Style::BOLD}#{Style::CYAN}│#{Style::RESET} Requests:      #{Style::BOLD}#{Style::MAGENTA}#{metrics[:total_requests]}#{Style::RESET} total processed".ljust(69) + "#{Style::BOLD}#{Style::CYAN}│#{Style::RESET}"
    
    bw_str = "Bandwidth:     ⬆️  #{format_bytes(metrics[:bytes_written])} written  /  ⬇️  #{format_bytes(metrics[:bytes_read])} read"
    puts "#{Style::BOLD}#{Style::CYAN}│#{Style::RESET} #{bw_str}".ljust(69) + "#{Style::BOLD}#{Style::CYAN}│#{Style::RESET}"
    
    avg_lat = metrics[:average_latency_us] ? metrics[:average_latency_us].to_f.round(2) : 0.0
    lat_color = avg_lat < 100 ? Style::GREEN : (avg_lat < 1000 ? Style::YELLOW : Style::RED)
    puts "#{Style::BOLD}#{Style::CYAN}│#{Style::RESET} Latency:       #{lat_color}#{avg_lat} μs#{Style::RESET} average per request".ljust(69) + "#{Style::BOLD}#{Style::CYAN}│#{Style::RESET}"
    puts "#{Style::BOLD}#{Style::CYAN}│#{Style::RESET} Errors:        #{metrics[:errors_encountered].to_i > 0 ? Style::RED : Style::GREEN}#{metrics[:errors_encountered]} encountered#{Style::RESET}".ljust(69) + "#{Style::BOLD}#{Style::CYAN}│#{Style::RESET}"
    
    puts "#{Style::BOLD}#{Style::CYAN}├──────────────────────────────────────────────────────────────┤#{Style::RESET}"
    puts "#{Style::BOLD}#{Style::CYAN}│ OPERATIONS BREAKDOWN:                                        │#{Style::RESET}"
    ops = metrics[:ops] || {}
    ops.each do |op_name, count|
      line = "  • #{op_name}:".ljust(18) + "#{Style::BOLD}#{Style::CYAN}#{count}#{Style::RESET} hits"
      puts "#{Style::BOLD}#{Style::CYAN}│#{Style::RESET} #{line}".ljust(69) + "#{Style::BOLD}#{Style::CYAN}│#{Style::RESET}"
    end
    puts "#{Style::BOLD}#{Style::CYAN}└──────────────────────────────────────────────────────────────┘#{Style::RESET}\n"
  end
end

# Main entry
begin
  # Load configuration if present to find binding settings
  config = {}
  if File.exist?(CONFIG_FILE)
    config = JSON.parse(File.read(CONFIG_FILE), symbolize_names: true) rescue {}
  end

  host = config[:host] || "127.0.0.1"
  port = config[:port] || 7401

  # Overrides from command line args
  host = ARGV[0] if ARGV[0]
  port = ARGV[1].to_i if ARGV[1]

  AdministrativeREPL.new(host, port).start
rescue Interrupt
  puts "\n#{Style::GRAY}Exiting Administrative Shell. Disconnected cleanly.#{Style::RESET}"
end
