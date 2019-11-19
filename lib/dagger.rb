require 'dagger/version'
require 'dagger/response'
require 'dagger/parsers'

require 'net/http/persistent'
require 'net/https'
require 'base64'

module Dagger

  DAGGER_NAME     = "Dagger/#{VERSION}"
  REDIRECT_CODES  = [301, 302, 303].freeze
  DEFAULT_RETRY_WAIT = 5.freeze # seconds
  DEFAULT_HEADERS = {
    'Accept'     => '*/*',
    'User-Agent' => "#{DAGGER_NAME} (Ruby Net::HTTP Wrapper, like curl)"
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
      uri = host + uri if uri['//'].nil? && host
      uri = parse_uri(uri)
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

    def self.init(uri, opts)
      uri  = Utils.parse_uri(uri)
      http = if opts.delete(:persistent)
        Net::HTTP::Persistent.new(name: DAGGER_NAME)
      else
        Net::HTTP.new(uri.host, uri.port)
      end

      if uri.port == 443
        http.use_ssl = true if http.respond_to?(:use_ssl) # persistent does it automatically
        http.verify_mode = opts[:verify_ssl] === false ? OpenSSL::SSL::VERIFY_NONE : OpenSSL::SSL::VERIFY_PEER
      end

      [:open_timeout, :read_timeout, :ssl_version, :ciphers].each do |key|
        http.send("#{key}=", opts[key]) if opts.has_key?(key)
      end

      new(http, [uri.scheme, uri.host].join('://'))
    end

    def initialize(http, host = nil)
      @http, @host = http, host
    end

    def get(uri, opts = {})
      uri = Utils.resolve_uri(uri, @host, opts[:query])

      opts[:follow] = 10 if opts[:follow] == true
      headers = opts[:headers] || {}
      headers['Accept'] = 'application/json' if opts[:json]

      request = Net::HTTP::Get.new(uri, DEFAULT_HEADERS.merge(headers))
      request.basic_auth(opts.delete(:username), opts.delete(:password)) if opts[:username]

      if @http.respond_to?(:started?) # regular Net::HTTP 
        @http.start unless @http.started?
        resp, data = @http.request(request)
      else # persistent
        resp, data = @http.request(uri, request)
      end

      if REDIRECT_CODES.include?(resp.code.to_i) && resp['Location'] && (opts[:follow] && opts[:follow] > 0)
        opts[:follow] -= 1
        puts "Following redirect to #{resp['Location']}"
        return get(resp['Location'], opts)
      end

      @response = build_response(resp, data || resp.body)

    rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ETIMEDOUT, Errno::EINVAL, Timeout::Error, \
      SocketError, EOFError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::ProtocolError, OpenSSL::SSL::SSLError => e

      if retries = opts[:retries] and retries.to_i > 0
        puts "Got #{e.class}! Retrying in a sec (#{retries} retries left)"
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
      headers = DEFAULT_HEADERS.merge(opts[:headers] || {})

      query = if data.is_a?(String)
        data
      elsif opts[:json]
        headers['Accept'] = headers['Content-Type'] = 'application/json'
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
        req.set_form_data(query)

        resp, data = @http.request(uri, req)
      end

      @response = build_response(resp, data || resp.body)

    rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ETIMEDOUT, Errno::EINVAL, Timeout::Error, \
      SocketError, EOFError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::ProtocolError, OpenSSL::SSL::SSLError => e

      if method.to_s.downcase != 'get' && retries = opts[:retries] and retries.to_i > 0
        puts "[#{DAGGER_NAME}] Got #{e.class}! Retrying in a sec (#{retries} retries left)"
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

    def build_response(resp, body)
      resp.extend(Response)
      resp.set_body(body) unless resp.body
      resp
    end

  end

  class << self

    def open(uri, opts = {}, &block)
      client = Client.init(uri, opts.merge(persistent: true))
      client.open(&block) if block_given?
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