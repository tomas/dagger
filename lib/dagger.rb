require 'dagger/version'
require 'dagger/response'
require 'dagger/parsers'
require 'net/http/persistent'
# require 'dagger/connection_manager' # unused
require 'net/https'
require 'base64'
require 'erb'

class URI::HTTP
  def scheme_and_host
    [scheme, host].join('://')
  end
end

module Dagger

  DAGGER_NAME     = "Dagger/#{VERSION}".freeze
  REDIRECT_CODES  = [301, 302, 303].freeze
  DEFAULT_RETRY_WAIT = 5.freeze # seconds
  DEFAULT_HEADERS = {
    'Accept'     => '*/*',
    'User-Agent' => "#{DAGGER_NAME} (Ruby Net::HTTP wrapper, like curl)"
  }.freeze

  DEFAULTS = {
    open_timeout: 10,
    read_timeout: 10,
    keep_alive_timeout: 10
  }.freeze

  module Utils

    def self.parse_uri(uri)
      raise ArgumentError.new("Empty URI") if uri.to_s.strip == ''
      uri = 'http://' + uri unless uri.to_s['http']
      uri = URI.parse(uri)
      raise ArgumentError.new("Invalid URI: #{uri}") unless uri.is_a?(URI::HTTP)
      uri.path = '/' if uri.path == ''
      uri
    end

    def self.resolve_uri(uri, host = nil, query = nil)
      uri = host + uri if uri.to_s[0] == '/' && host
      uri = parse_uri(uri.to_s)
      uri.path.sub!(/\?.*|$/, '?' + to_query_string(query)) if query and query.any?
      uri
    end

    def self.encode_body(obj, opts = {})
      return if obj.nil? || obj.empty?
      if obj.is_a?(String)
        obj
      elsif opts[:json]
        Oj.dump(obj, mode: :compat) # compat ensures symbols are converted to strings
      else
        to_query_string(obj)
      end
    end

    def self.to_query_string(obj, key = nil)
      if key.nil? && obj.is_a?(String) # && obj['=']
        return obj
      end

      case obj
      when Hash  then obj.map { |k, v| to_query_string(v, append_key(key, k)) }.join('&')
      when Array then obj.map { |v| to_query_string(v, "#{key}[]") }.join('&')
      when nil   then ''
      else
        "#{key}=#{ERB::Util.url_encode(obj.to_s)}"
      end
    end

    def self.append_key(root_key, key)
      root_key.nil? ? key : "#{root_key}[#{key.to_s}]"
    end

  end

  class Client

    def self.init_connection(uri, opts = {})
      http = if opts.delete(:persistent)
        pool_size = opts[:pool_size] || Net::HTTP::Persistent::DEFAULT_POOL_SIZE
        Net::HTTP::Persistent.new(name: DAGGER_NAME, pool_size: pool_size)
      else
        Net::HTTP.new(opts[:ip] || uri.host, uri.port)
      end

      if uri.port == 443 || uri.scheme == 'https'
        http.use_ssl = true if http.respond_to?(:use_ssl=) # persistent does it automatically
        http.verify_mode = opts[:verify_ssl] === false ? OpenSSL::SSL::VERIFY_NONE : OpenSSL::SSL::VERIFY_PEER
      end

      [:open_timeout, :read_timeout, :ssl_version, :ciphers].each do |key|
        http.send("#{key}=", opts[key] || DEFAULTS[key]) if (opts.has_key?(key) || DEFAULTS.has_key?(key))
      end

      http
    end

    def self.init(uri, opts)
      uri  = Utils.parse_uri(uri)
      http = init_connection(uri, opts)

      new(http, uri.scheme_and_host)
    end

    def initialize(http, host = nil)
      @http, @host = http, host
    end

    def get(uri, opts = {})
      uri = Utils.resolve_uri(uri, @host, opts[:query])

      if @host != uri.scheme_and_host
        raise ArgumentError.new("#{uri.scheme_and_host} does not match #{@host}")
      end

      opts[:follow] = 10 if opts[:follow] == true
      headers = opts[:headers] || {}
      headers['Accept'] = 'application/json' if opts[:json] && headers['Accept'].nil?
      headers['Content-Type'] = 'application/json' if opts[:json] && opts[:body] && opts[:body].size > 0

      if opts[:ip]
        headers['Host'] = uri.host
        uri = opts[:ip]
      end

      debug { "Sending GET request to #{uri.request_uri} with headers #{headers.inspect} -- #{opts[:body]}" }

      request = Net::HTTP::Get.new(uri, DEFAULT_HEADERS.merge(headers))
      request.basic_auth(opts.delete(:username), opts.delete(:password)) if opts[:username]
      request.body = Utils.encode_body(opts[:body], opts) if opts[:body] && opts[:body].size > 0

      if @http.respond_to?(:started?) # regular Net::HTTP
        @http.start unless @http.started?
        resp, data = @http.request(request)
      else # persistent
        resp, data = @http.request(uri, request)
      end

      if REDIRECT_CODES.include?(resp.code.to_i) && resp['Location'] && (opts[:follow] && opts[:follow] > 0)
        opts[:follow] -= 1
        debug { "Following redirect to #{resp['Location']}" }
        return get(resp['Location'], opts)
      end

      @response = build_response(resp, data || resp.body)

    rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ETIMEDOUT, Errno::EINVAL, Timeout::Error, \
      Net::OpenTimeout, Net::ReadTimeout, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::ProtocolError, \
      SocketError, EOFError, OpenSSL::SSL::SSLError => e

      if retries = opts[:retries] and retries.to_i > 0
        debug { "Got #{e.class}! Retrying in a sec (#{retries} retries left)" }
        sleep (opts[:retry_wait] || DEFAULT_RETRY_WAIT)
        get(uri, opts.merge(retries: retries - 1))
      else
        raise
      end
    end

    def post(uri, data, options = {})
      request(:post, uri, data, options)
    end

    def put(uri, data, options = {})
      request(:put, uri, data, options)
    end

    def patch(uri, data, options = {})
      request(:patch, uri, data, options)
    end

    def delete(uri, data, options = {})
      request(:delete, uri, data, options)
    end

    def request(method, uri, data, opts = {})
      if method.to_s.downcase == 'get'
        data ||= opts[:body]
        return get(uri, opts.merge(body: data))
      end

      uri = Utils.resolve_uri(uri, @host, opts[:query])
      if @host != uri.scheme_and_host
        raise ArgumentError.new("#{uri.scheme_and_host} does not match #{@host}")
      end

      headers = DEFAULT_HEADERS.merge(opts[:headers] || {})
      body = Utils.encode_body(data, opts)

      if opts[:username] # opts[:password] is optional
        str = [opts[:username], opts[:password]].compact.join(':')
        headers['Authorization'] = 'Basic ' + Base64.strict_encode64(str)
      end

      if opts[:json]
        headers['Content-Type'] = 'application/json'
        headers['Accept'] = 'application/json' if headers['Accept'].nil?
      end

      start = Time.now
      debug { "Sending #{method} request to #{uri.request_uri} with headers #{headers.inspect} -- #{data}" }

      if @http.respond_to?(:started?) # regular Net::HTTP
        args = [method.to_s.downcase, uri.request_uri, body, headers]
        args.delete_at(2) if args[0] == 'delete' # Net::HTTP's delete does not accept data

        @http.start unless @http.started?
        resp, data = @http.send(*args)
      else # Net::HTTP::Persistent
        req = Kernel.const_get("Net::HTTP::#{method.capitalize}").new(uri.request_uri, headers)
        req.body = body
        resp, data = @http.request(uri, req)
      end

      debug { "Got response #{resp.code} in #{(Time.now - start).round(2)}s: #{data || resp.body}" }
      @response = build_response(resp, data || resp.body)

    rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ETIMEDOUT, Errno::EINVAL, Timeout::Error, \
      Net::OpenTimeout, Net::ReadTimeout, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::ProtocolError, \
      SocketError, EOFError, OpenSSL::SSL::SSLError => e

      if method.to_s.downcase != 'get' && retries = opts[:retries] and retries.to_i > 0
        debug { "Got #{e.class}! Retrying in a sec (#{retries} retries left)" }
        sleep (opts[:retry_wait] || DEFAULT_RETRY_WAIT)
        request(method, uri, data, opts.merge(retries: retries - 1))
      else
        raise
      end
    end

    def response
      @response or raise 'Request not sent!'
    end

    def open(&block)
      if @http.is_a?(Net::HTTP::Persistent)
        instance_eval(&block)
      else
        @http.start do
          instance_eval(&block)
        end
      end
    end

    def close
      if @http.is_a?(Net::HTTP::Persistent)
        @http.shutdown # calls finish on pool connections
      else
        @http.finish if @http.started?
      end
    end

    private

    def debug(&block)
      if ENV['DEBUGGING'] || ENV['DEBUG']
        str = yield
        logger.info "[#{DAGGER_NAME}] #{str}"
      end
    end

    def logger
      require 'logger'
      @logger ||= Logger.new(@logfile || STDOUT)
    end

    def build_response(resp, body)
      resp.extend(Response)
      resp.set_body(body) unless resp.body
      resp
    end

  end

  class << self

    def open(uri, opts = {}, &block)
      client = Client.init(uri, opts.merge(persistent: true))
      if block_given?
        client.open(&block)
        client.close
      end
      client
    end

    def get(uri, options = {})
      request(:get, uri, nil, options)
    end

    def post(uri, data, options = {})
      request(:post, uri, data, options)
    end

    def put(uri, data, options = {})
      request(:put, uri, data, options)
    end

    def patch(uri, data, options = {})
      request(:patch, uri, data, options)
    end

    def delete(uri, data, options = {})
      request(:delete, uri, data, options)
    end

    def request(method, url, data = {}, options = {})
      Client.init(url, options).request(method, url, data, options)
    end

  end

end
