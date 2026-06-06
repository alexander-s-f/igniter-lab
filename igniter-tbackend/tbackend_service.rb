# frozen_string_literal: true

require "json"
require "fileutils"
require "socket"
require "zlib"

Dir.chdir(__dir__)

PID_FILE = "tbackend.pid"
CONFIG_FILE = "tbackend.config.json"

# ANSI styling helper module matching our TodoApp UI style
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

def load_config
  unless File.exist?(CONFIG_FILE)
    puts "#{Style::RED}Error: #{CONFIG_FILE} not found! Please create it.#{Style::RESET}"
    exit 1
  end
  JSON.parse(File.read(CONFIG_FILE), symbolize_names: true)
end

def running_pid(pid)
  begin
    Process.kill(0, pid)
    pid
  rescue Errno::ESRCH, Errno::EPERM
    nil
  end
end

def current_pid
  if File.exist?(PID_FILE)
    pid = File.read(PID_FILE).to_i
    running_pid(pid)
  else
    nil
  end
end

def start_server
  pid = current_pid
  if pid
    puts "#{Style::YELLOW}[Service] TBackend is already running (PID: #{pid}).#{Style::RESET}"
    return
  end

  config = load_config
  log_path = config[:log_path] || "tbackend.log"
  host = config[:host] || "127.0.0.1"
  port = config[:port] || 7401

  puts "#{Style::BOLD}#{Style::CYAN}Starting TBackend Server...#{Style::RESET}"
  
  # Spawn run_server.rb detaching the process group and redirecting output
  pid = spawn("ruby run_server.rb", out: [log_path, "a"], err: [log_path, "a"], pgroup: true)
  Process.detach(pid)
  File.write(PID_FILE, pid)

  puts "#{Style::GREEN}✔ TBackend Server started in background!#{Style::RESET}"
  puts "  #{Style::BOLD}PID:#{Style::RESET} #{pid}"
  puts "  #{Style::BOLD}Log:#{Style::RESET} #{log_path}"
  puts "  #{Style::BOLD}Host/Port:#{Style::RESET} #{host}:#{port}"
end

def stop_server
  pid = current_pid
  if pid.nil?
    puts "#{Style::YELLOW}[Service] No active PID file found. Server is offline.#{Style::RESET}"
    # Cleanup stale PID file if any
    FileUtils.rm_f(PID_FILE)
    return
  end

  puts "#{Style::BOLD}#{Style::CYAN}Stopping TBackend Server (PID: #{pid})...#{Style::RESET}"
  begin
    Process.kill("TERM", pid)
  rescue Errno::ESRCH
    # Already dead
  end

  # Poll for up to 5 seconds to exit gracefully
  stopped = false
  50.times do
    unless running_pid(pid)
      stopped = true
      break
    end
    sleep 0.1
  end

  if !stopped
    puts "#{Style::RED}Server did not exit gracefully. Forcing SIGKILL...#{Style::RESET}"
    begin
      Process.kill("KILL", pid)
    rescue Errno::ESRCH
      # Already dead
    end
  end

  FileUtils.rm_f(PID_FILE)
  puts "#{Style::GREEN}✔ TBackend Server stopped successfully.#{Style::RESET}"
end

def restart_server
  stop_server
  sleep 0.5
  start_server
end

def query_metrics(host, port)
  socket = TCPSocket.new(host, port)
  socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, true)
  
  body = JSON.generate({ op: "metrics" }).b
  frame = [body.bytesize].pack("N") << body << [Zlib.crc32(body)].pack("N")
  socket.write(frame)
  
  header = socket.read(4)
  return nil unless header && header.bytesize == 4
  len = header.unpack1("N")
  
  resp_body = socket.read(len)
  return nil unless resp_body && resp_body.bytesize == len
  
  crc_bytes = socket.read(4)
  return nil unless crc_bytes && crc_bytes.bytesize == 4
  
  JSON.parse(resp_body, symbolize_names: true)
rescue
  nil
ensure
  socket.close rescue nil
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

def print_status
  config = load_config
  host = config[:host] || "127.0.0.1"
  port = config[:port] || 7401
  log_path = config[:log_path] || "tbackend.log"
  
  pid = current_pid
  metrics = pid ? query_metrics(host, port) : nil

  puts "\n#{Style::BOLD}#{Style::CYAN}┌──────────────────────────────────────────────────────────────┐#{Style::RESET}"
  puts "#{Style::BOLD}#{Style::CYAN}│                  #{Style::MAGENTA}TBACKEND TELEMETRY DASHBOARD#{Style::CYAN}                │#{Style::RESET}"
  puts "#{Style::BOLD}#{Style::CYAN}├──────────────────────────────────────────────────────────────┤#{Style::RESET}"
  
  if pid && metrics
    puts "#{Style::BOLD}#{Style::CYAN}│#{Style::RESET} Status:        #{Style::GREEN}🟢 Active / Online#{Style::RESET}                            #{Style::BOLD}#{Style::CYAN}│#{Style::RESET}"
    puts "#{Style::BOLD}#{Style::CYAN}│#{Style::RESET} Host/Port:     #{Style::WHITE}#{host}:#{port}#{Style::RESET}".ljust(69) + "#{Style::BOLD}#{Style::CYAN}│#{Style::RESET}"
    puts "#{Style::BOLD}#{Style::CYAN}│#{Style::RESET} Process ID:    #{Style::WHITE}#{pid}#{Style::RESET}".ljust(69) + "#{Style::BOLD}#{Style::CYAN}│#{Style::RESET}"
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
  else
    puts "#{Style::BOLD}#{Style::CYAN}│#{Style::RESET} Status:        #{Style::RED}🔴 Offline / Closed#{Style::RESET}                           #{Style::BOLD}#{Style::CYAN}│#{Style::RESET}"
    puts "#{Style::BOLD}#{Style::CYAN}│#{Style::RESET} Host/Port:     #{host}:#{port}".ljust(61) + " #{Style::BOLD}#{Style::CYAN}│#{Style::RESET}"
    puts "#{Style::BOLD}#{Style::CYAN}│#{Style::RESET} Configuration: metrics tracking will activate on boot.        #{Style::BOLD}#{Style::CYAN}│#{Style::RESET}"
    puts "#{Style::BOLD}#{Style::CYAN}│#{Style::RESET} Log File:      #{log_path}".ljust(61) + " #{Style::BOLD}#{Style::CYAN}│#{Style::RESET}"
  end
  
  puts "#{Style::BOLD}#{Style::CYAN}└──────────────────────────────────────────────────────────────┘#{Style::RESET}\n"
end

def tail_log
  config = load_config
  log_path = config[:log_path] || "tbackend.log"
  unless File.exist?(log_path)
    puts "#{Style::YELLOW}Log file '#{log_path}' is empty or does not exist yet.#{Style::RESET}"
    return
  end

  puts "#{Style::BOLD}#{Style::CYAN}Tailing last 30 lines of: #{log_path}... (Press Ctrl+C to exit)#{Style::RESET}\n"
  
  # Print last 30 lines first
  lines = File.readlines(log_path)
  start_idx = [0, lines.size - 30].max
  lines[start_idx..].each { |l| print l }

  # Simple tail -f implementation
  begin
    File.open(log_path, "r") do |file|
      file.seek(0, IO::SEEK_END)
      loop do
        line = file.gets
        if line
          print line
        else
          sleep 0.1
        end
      end
    end
  rescue Interrupt
    puts "\n#{Style::GRAY}Exiting log view.#{Style::RESET}"
  end
end

def dump_raw_metrics
  config = load_config
  host = config[:host] || "127.0.0.1"
  port = config[:port] || 7401
  
  metrics = query_metrics(host, port)
  if metrics
    puts JSON.pretty_generate(metrics)
  else
    puts JSON.generate({ ok: false, error: "Server offline or metrics unavailable" })
  end
end

case ARGV.first&.downcase
when "start"
  start_server
when "stop"
  stop_server
when "restart"
  restart_server
when "status"
  print_status
when "log"
  tail_log
when "metrics"
  dump_raw_metrics
else
  puts "#{Style::BOLD}#{Style::CYAN}TBackend Service Manager#{Style::RESET}"
  puts "Usage:"
  puts "  ruby tbackend_service.rb start      - Start server as a daemon"
  puts "  ruby tbackend_service.rb stop       - Stop the daemon"
  puts "  ruby tbackend_service.rb restart    - Restart the daemon"
  puts "  ruby tbackend_service.rb status     - Inspect telemetry dashboard"
  puts "  ruby tbackend_service.rb log        - Tail the server log file"
  puts "  ruby tbackend_service.rb metrics    - Dump raw JSON metrics payload"
  puts ""
end
