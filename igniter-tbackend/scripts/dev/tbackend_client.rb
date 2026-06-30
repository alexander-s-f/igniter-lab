# frozen_string_literal: true

require "json"
require "socket"
require "timeout"
require "zlib"

class TBackendClient
  DEFAULT_HOST = "127.0.0.1"
  DEFAULT_PORT = 7401
  DEFAULT_CONNECT_TIMEOUT = 1.0
  DEFAULT_REQUEST_TIMEOUT = 2.0
  MAX_FRAME_BYTES = 64 * 1024 * 1024

  class TransportUnavailable < StandardError; end
  class TransportUnknown < StandardError; end
  class InvalidFrame < StandardError; end

  def initialize(host: DEFAULT_HOST, port: DEFAULT_PORT, token: nil,
                 connect_timeout: DEFAULT_CONNECT_TIMEOUT,
                 request_timeout: DEFAULT_REQUEST_TIMEOUT,
                 strict: false)
    @host = host
    @port = Integer(port)
    @token = token
    @connect_timeout = Float(connect_timeout)
    @request_timeout = Float(request_timeout)
    @strict = strict
  end

  def ping(timeout: nil)
    map_generic_response(request({ op: "ping" }, timeout: timeout))
  end

  def facts_for(store:, key: nil, since: nil, as_of: nil, timeout: nil)
    req = { op: "facts_for", store: store }
    req[:key] = key unless key.nil?
    req[:since] = since unless since.nil?
    req[:as_of] = as_of unless as_of.nil?
    map_generic_response(request(req, timeout: timeout))
  end

  def size(store: nil, timeout: nil)
    req = { op: "size" }
    req[:store] = store unless store.nil?
    map_generic_response(request(req, timeout: timeout))
  end

  def write_fact_once(fact, timeout: nil)
    map_write_once_response(request({ op: "write_fact_once", fact: fact }, timeout: timeout))
  end

  def write_fact_once_safe(fact, timeout: nil, attempts: 2, backoff: 0.05)
    max_attempts = [Integer(attempts), 1].max
    seen = []

    max_attempts.times do |index|
      result = write_fact_once(fact, timeout: timeout)
      seen << attempt_summary(result)

      unless retry_safe_status?(result[:status]) && index + 1 < max_attempts
        return result.merge(attempt_count: seen.length, attempts: seen)
      end

      sleep(backoff.to_f) if backoff.to_f.positive?
    end
  end

  private

  def request(req, timeout:)
    raw = raw_request(with_token(req), request_timeout(timeout))
    { transport_ok: true, response: raw }
  rescue TransportUnavailable => e
    raise if @strict

    transport_result("unavailable", e, retryable: true)
  rescue TransportUnknown => e
    raise if @strict

    transport_result("timeout_unknown", e, retryable: nil)
  end

  def raw_request(req, timeout)
    socket = open_socket
    Timeout.timeout(timeout) do
      socket.write(encode_frame(req))
      decode_frame(socket)
    end
  rescue Timeout::Error, EOFError, IOError, SystemCallError, JSON::ParserError, InvalidFrame => e
    raise TransportUnknown, e.message
  ensure
    socket.close if socket && !socket.closed?
  end

  def open_socket
    socket = nil
    Timeout.timeout(@connect_timeout) do
      socket = TCPSocket.new(@host, @port)
    end
    socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, true)
    socket
  rescue Timeout::Error, SocketError, SystemCallError => e
    raise TransportUnavailable, e.message
  end

  def with_token(req)
    copy = req.dup
    copy[:token] = @token if @token && !@token.to_s.empty? && !copy.key?(:token) && !copy.key?("token")
    copy
  end

  def request_timeout(override)
    override.nil? ? @request_timeout : Float(override)
  end

  def encode_frame(req)
    body = JSON.generate(req).b
    [body.bytesize].pack("N") + body + [Zlib.crc32(body)].pack("N")
  end

  def decode_frame(socket)
    header = read_exact(socket, 4)
    len = header.unpack1("N")
    raise InvalidFrame, "response frame too large" if len > MAX_FRAME_BYTES

    body = read_exact(socket, len)
    expected_crc = read_exact(socket, 4).unpack1("N")
    actual_crc = Zlib.crc32(body)
    raise InvalidFrame, "CRC mismatch" unless expected_crc == actual_crc

    JSON.parse(body, symbolize_names: true)
  end

  def read_exact(socket, bytes)
    data = +"".b
    while data.bytesize < bytes
      chunk = socket.read(bytes - data.bytesize)
      raise EOFError, "socket closed" if chunk.nil? || chunk.empty?

      data << chunk
    end
    data
  end

  def map_write_once_response(envelope)
    return envelope unless envelope[:transport_ok]

    response = envelope[:response]
    return rejected_before_commit(response) if overloaded_before_commit?(response)
    return duplicate_conflict(response) if response[:error_code] == "duplicate_fact_id_conflict"

    if response[:ok] == true && response[:committed] == true
      if response[:idempotent_replay] == true
        return result(true, "idempotent_replay", true, false, response, nil)
      end

      return result(true, "committed_acked", true, false, response, nil)
    end

    generic_error(response)
  end

  def map_generic_response(envelope)
    return envelope unless envelope[:transport_ok]

    response = envelope[:response]
    return result(true, "ok", nil, false, response, nil) if response[:ok] == true
    return rejected_before_commit(response) if overloaded_before_commit?(response)

    generic_error(response)
  end

  def overloaded_before_commit?(response)
    response[:error_code] == "overloaded" && response[:committed] == false
  end

  def rejected_before_commit(response)
    result(false, "rejected_before_commit", false, true, response, response[:error])
  end

  def duplicate_conflict(response)
    result(false, "duplicate_fact_id_conflict", false, false, response, response[:error])
  end

  def generic_error(response)
    result(false, "error", response[:committed], response[:retryable], response, response[:error])
  end

  def transport_result(status, error, retryable:)
    result(false, status, nil, retryable, nil, sanitize_error(error))
  end

  def result(ok, status, committed, retryable, response, error)
    {
      ok: ok,
      status: status,
      committed: committed,
      retryable: retryable,
      response: response,
      error: error
    }
  end

  def retry_safe_status?(status)
    status == "rejected_before_commit" || status == "timeout_unknown"
  end

  def attempt_summary(result)
    {
      ok: result[:ok],
      status: result[:status],
      committed: result[:committed],
      retryable: result[:retryable]
    }
  end

  def sanitize_error(error)
    text = "#{error.class}: #{error.message}"
    return text unless @token && !@token.to_s.empty?

    text.gsub(@token.to_s, "[REDACTED]")
  end
end
