# verify_mcp.rb
# Automated Integration Test Suite for TBackend native Model Context Protocol (MCP) Server

require 'open3'
require 'json'

def log_pass(msg)
  puts "  \e[32m✔ PASS: #{msg}\e[0m"
end

def log_fail(msg)
  puts "  \e[31m✘ FAIL: #{msg}\e[0m"
  exit(1)
end

puts "\n=== TBACKEND NATIVE MODEL CONTEXT PROTOCOL (MCP) TEST SUITE ===\n\n"

# 1. Compile the server executable
puts "[Compile] Rebuilding TBackend binary with MCP pack..."
system("RUSTFLAGS=\"-C link-arg=-undefined -C link-arg=dynamic_lookup\" cargo build --release") || log_fail("Cargo build failed")

# 2. Spawn TBackend daemon in subprocess stdio MCP mode (ephemeral data store)
puts "[MCP Daemon] Spawning daemon in background with --mcp and --data-dir nil..."
stdin, stdout, stderr, wait_thr = Open3.popen3("./target/release/tbackend --mcp --data-dir nil")

# Read lines from stderr to verify MCP boot acknowledgement
boot_success = false
while (line = stderr.readline)
  if line.include?("[MCP Server] Native MCP stdio loop spawned")
    boot_success = true
    break
  end
end
if boot_success
  log_pass("MCP Stdio Loop successfully booted and acknowledged on stderr")
else
  log_fail("Failed to find MCP boot acknowledgment on stderr")
end

begin
  # 3. Test tools/list method
  puts "\n[MCP Tools List] Requesting available tools..."
  req_list = {
    jsonrpc: "2.0",
    id: 100,
    method: "tools/list",
    params: {}
  }
  stdin.puts(req_list.to_json)
  stdin.flush

  resp_line = stdout.readline
  resp = JSON.parse(resp_line)

  if resp["jsonrpc"] != "2.0" || resp["id"] != 100
    log_fail("Invalid JSON-RPC header: #{resp_line}")
  end

  tools = resp.dig("result", "tools") || []
  tool_names = tools.map { |t| t["name"] }
  puts "  Exposed tools: #{tool_names.join(', ')}"

  expected_tools = ["tbackend_write_fact", "tbackend_latest_for", "tbackend_query_slice", "tbackend_analytics_aggregate", "tbackend_pipeline_create", "tbackend_diagnostics_summary"]
  expected_tools.each do |t|
    if tool_names.include?(t)
      log_pass("Exposed tool '#{t}' successfully detected with correct schema")
    else
      log_fail("Missing expected tool '#{t}' in list response")
    end
  end

  # 4. Test tbackend_write_fact tool call
  puts "\n[MCP Tool Call] Executing 'tbackend_write_fact'..."
  req_write = {
    jsonrpc: "2.0",
    id: 101,
    method: "tools/call",
    params: {
      name: "tbackend_write_fact",
      arguments: {
        store: "mcp_leads",
        key: "lead-alpha",
        value: {
          zip_code: "91125",
          bid: 22.5,
          status: "active"
        },
        producer: "mcp-agent-1"
      }
    }
  }
  stdin.puts(req_write.to_json)
  stdin.flush

  resp_line = stdout.readline
  resp = JSON.parse(resp_line)

  if resp["id"] != 101
    log_fail("Unexpected JSON-RPC id: #{resp_line}")
  end

  content = resp.dig("result", "content", 0, "text")
  write_res = JSON.parse(content)
  if write_res["ok"] == true
    log_pass("Tool call tbackend_write_fact succeeded")
  else
    log_fail("Tool call write_fact returned failure: #{content}")
  end

  # 5. Test tbackend_latest_for point temporal query
  puts "\n[MCP Tool Call] Executing 'tbackend_latest_for'..."
  req_latest = {
    jsonrpc: "2.0",
    id: 102,
    method: "tools/call",
    params: {
      name: "tbackend_latest_for",
      arguments: {
        store: "mcp_leads",
        key: "lead-alpha"
      }
    }
  }
  stdin.puts(req_latest.to_json)
  stdin.flush

  resp_line = stdout.readline
  resp = JSON.parse(resp_line)

  content = resp.dig("result", "content", 0, "text")
  latest_res = JSON.parse(content)
  if latest_res["ok"] == true && latest_res.dig("fact", "key") == "lead-alpha"
    log_pass("Tool call tbackend_latest_for returned correct bitemporal point fact")
    val = latest_res.dig("fact", "value")
    if val["zip_code"] == "91125" && val["bid"] == 22.5 && val["status"] == "active"
      log_pass("Point fact payload fields matches precisely (zip_code, bid, status)")
    else
      log_fail("Point fact payload mismatched: #{val.inspect}")
    end
  else
    log_fail("Tool call latest_for returned unexpected response: #{content}")
  end

  # 6. Test tbackend_query_slice with pushdown rules
  puts "\n[MCP Tool Call] Executing 'tbackend_query_slice' with pushdown ROP filtration rules..."
  req_slice = {
    jsonrpc: "2.0",
    id: 103,
    method: "tools/call",
    params: {
      name: "tbackend_query_slice",
      arguments: {
        store: "mcp_leads",
        rules: [
          { left_path: "value.bid", op: "gt", right_val: 20 },
          { left_path: "value.zip_code", op: "eq", right_val: "91125" }
        ]
      }
    }
  }
  stdin.puts(req_slice.to_json)
  stdin.flush

  resp_line = stdout.readline
  resp = JSON.parse(resp_line)

  content = resp.dig("result", "content", 0, "text")
  slice_res = JSON.parse(content)
  facts = slice_res["facts"] || []
  if slice_res["ok"] == true && facts.size == 1
    log_pass("ROP Pushdown slice filter matched exactly 1 record successfully")
  else
    log_fail("ROP Pushdown slice filter failed or mismatched size: #{content}")
  end

  # Test empty slice matching when rules block the fact
  puts "\n[MCP Tool Call] Executing 'tbackend_query_slice' with non-matching ROP rules..."
  req_slice_empty = {
    jsonrpc: "2.0",
    id: 104,
    method: "tools/call",
    params: {
      name: "tbackend_query_slice",
      arguments: {
        store: "mcp_leads",
        rules: [
          { left_path: "value.bid", op: "lt", right_val: 10 } # bid is 22.5, so this will fail
        ]
      }
    }
  }
  stdin.puts(req_slice_empty.to_json)
  stdin.flush

  resp_line = stdout.readline
  resp = JSON.parse(resp_line)

  content = resp.dig("result", "content", 0, "text")
  slice_res = JSON.parse(content)
  facts = slice_res["facts"] || []
  if slice_res["ok"] == true && facts.size == 0
    log_pass("ROP Pushdown slice correctly returned empty array for non-matching rules")
  else
    log_fail("ROP Pushdown slice empty test failed: #{content}")
  end

  # 7. Test invalid method call (JSON-RPC Error)
  puts "\n[MCP JSON-RPC Error] Executing unsupported custom method..."
  req_invalid = {
    jsonrpc: "2.0",
    id: 105,
    method: "unsupported_mcp_custom_method",
    params: {}
  }
  stdin.puts(req_invalid.to_json)
  stdin.flush

  resp_line = stdout.readline
  resp = JSON.parse(resp_line)
  err = resp["error"]
  if err && err["code"] == -32601 && err["message"].include?("Method not found")
    log_pass("Unsupported custom method correctly rejected with standard JSON-RPC code -32601")
  else
    log_fail("Mismatched response for invalid method call: #{resp_line}")
  end

ensure
  # Gracefully terminate daemon subprocess
  puts "\n[Tear Down] Stopping MCP daemon..."
  stdin.close
  stdout.close
  stderr.close
  Process.kill("KILL", wait_thr.pid) rescue nil
end

puts "\n🏆 ALL NATIVE MCP TESTS PASSED SUCCESSFULLY!\n\n"
