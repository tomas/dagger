require 'dagger/version'
require 'dagger/response'
require 'dagger/parsers'
require 'dagger/connection_manager'
require 'net/https'
require 'base64'

class URI::HTTP
  def scheme_and_host
    [scheme, host].join('://')
  end
end

module Dagger

  DAGGER_NAME     = "Dagger/#{VERSION}"
  REDIRECT_CODES  = [301, 302, 303].freeze
  DEFAULT_RETRY_WAIT = 5.freeze # seconds
  DEFAULT_HEADERS = {
    'Accept'     => '*/*',
    'User-Agent' => "#{DAGGER_NAME} (Ruby Net::HTTP wrapper, like curl)"
  }

  DEFAULTS = {
    open_timeout: 10,
    read_timeout: 10,
    keep_alive_timeout: 10
  }

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
      uri = host + uri if uri.to_s['//'].nil? && host
      uri = parse_uri(uri.to_s)
      uri.path.sub!(/\?.*|$/, '?' + Utils.encode(query)) if query and query.any?
      uri
    end

    def self.encode(obj, key = nil)
      if key.nil? && obj.is_a?(String) # && obj['=']
        return obj
      end

      case obj
      when Hash  then obj.map { |k, v| encode(v, append_key(key,k)) }.join('&')
      when Array then obj.map { |v| encode(v, "#{key}[]") }.join('&')
      when nil   then ''
      else
        "#{key}=#{URI.escape(obj.to_s)}"
      end
    end

    def self.append_key(root_key, key)
      root_key.nil? ? key : "#{root_key}[#{key.to_s}]"
    end

  end

  class Client

    def self.init_persistent(opts = {})
      # this line below forces one connection manager between multiple threads
      # @persistent ||= Dagger::ConnectionManager.new(opts)

      # here we initialize a connection manager for each thread
      Thread.current[:dagger_persistent] ||= begin
        Dagger::ConnectionManager.new(opts)
      end
    end

    def self.init_connection(uri, opts = {})
      http = Net::HTTP.new(opts[:ip] || uri.host, uri.port)

      if uri.port == 443
        http.use_ssl = true if http.respond_to?(:use_ssl=) # persistent does it automatically
        http.verify_mode = opts[:verify_ssl] === false ? OpenSSL::SSL::VERIFY_NONE : OpenSSL::SSL::VERIFY_PEER
      end

      [:keep_alive_timeout, :open_timeout, :read_timeout, :ssl_version, :ciphers].each do |key|
        http.send("#{key}=", opts[key] || DEFAULTS[key]) if (opts.has_key?(key) || DEFAULTS.has_key?(key))
      end

      http
    end

    def self.init(uri, opts)
      uri  = Utils.parse_uri(uri)

      http = if opts.delete(:persistent)
        init_persistent(opts)
      else
        init_connection(uri, opts)
      end

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

      if opts[:ip]
        headers['Host'] = uri.host
        uri = opts[:ip]
      end

      request = Net::HTTP::Get.new(uri, DEFAULT_HEADERS.merge(headers))
      request.basic_auth(opts.delete(:username), opts.delete(:password)) if opts[:username]

      if @http.respond_to?(:started?) # regular Net::HTTP
        @http.start unless @http.started?
        resp, data = @http.request(request)
      else # persistent
        resp, data = @http.send_request(uri, request)
      end

      if REDIRECT_CODES.include?(resp.code.to_i) && resp['Location'] && (opts[:follow] && opts[:follow] > 0)
        opts[:follow] -= 1
        debug "Following redirect to #{resp['Location']}"
        return get(resp['Location'], opts)
      end

      @response = build_response(resp, data || resp.body)

    rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ETIMEDOUT, Errno::EINVAL, Timeout::Error, \
      Net::OpenTimeout, Net::ReadTimeout, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::ProtocolError, \
      SocketError, EOFError, OpenSSL::SSL::SSLError => e

      if retries = opts[:retries] and retries.to_i > 0
        debug "Got #{e.class}! Retrying in a sec (#{retries} retries left)"
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
        query = (opts[:query] || {}).merge(data || {})
        return get(uri, opts.merge(query: query))
      end

      uri = Utils.resolve_uri(uri, @host)
      if @host != uri.scheme_and_host
        raise ArgumentError.new("#{uri.scheme_and_host} does not match #{@host}")
      end

      headers = DEFAULT_HEADERS.merge(opts[:headers] || {})

      query = if data.is_a?(String)
        data
      elsif opts[:json]
        headers['Content-Type'] = 'application/json'
        headers['Accept'] = 'application/json' if headers['Accept'].nil?
        Oj.dump(data, mode: :compat) # compat ensures symbols are converted to strings
      else # querystring, then
        Utils.encode(data)
      end

      if opts[:username] # opts[:password] is optional
        str = [opts[:username], opts[:password]].compact.join(':')
        headers['Authorization'] = 'Basic ' + Base64.encode64(str)
      end

      if @http.respond_to?(:started?) # regular Net::HTTP
        args = [method.to_s.downcase, uri.path, query, headers]
        args.delete_at(2) if args[0] == 'delete' # Net::HTTP's delete does not accept data

        @http.start unless @http.started?
        resp, data = @http.send(*args)
      else # Net::HTTP::Persistent
        req = Kernel.const_get("Net::HTTP::#{method.capitalize}").new(uri.path, headers)
        # req.set_form_data(query)
        req.body = query
        resp, data = @http.send_request(uri, req)
      end

      @response = build_response(resp, data || resp.body)

    rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ETIMEDOUT, Errno::EINVAL, Timeout::Error, \
      Net::OpenTimeout, Net::ReadTimeout, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::ProtocolError, \
      SocketError, EOFError, OpenSSL::SSL::SSLError => e

      if method.to_s.downcase != 'get' && retries = opts[:retries] and retries.to_i > 0
        debug "[#{DAGGER_NAME}] Got #{e.class}! Retrying in a sec (#{retries} retries left)"
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
      if @http.is_a?(Dagger::ConnectionManager)
        instance_eval(&block)
      else
        @http.start do
          instance_eval(&block)
        end
      end
    end

    def close
      if @http.is_a?(Dagger::ConnectionManager)
        @http.shutdown # calls finish on pool connections
      else
        @http.finish if @http.started?
      end
    end

    private

    def debug(str)
      puts str if ENV['DEBUGGING']
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