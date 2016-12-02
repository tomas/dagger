# Dagger.
require 'dagger/version'
require 'dagger/response'
require 'dagger/parsers'

require 'net/https'
require 'base64'

module Dagger

  REDIRECT_CODES  = [301, 302, 303].freeze
  DEFAULT_HEADERS = {
    'Accept'     => '*/*',
    'User-Agent' => "Dagger/#{VERSION} (Ruby Net::HTTP Wrapper, like curl)"
  }

  module Utils

    def self.parse_uri(uri)
      uri = 'http://' + uri unless uri.to_s['http']
      uri = URI.parse(uri)
      raise ArgumentError.new("Invalid URI: #{uri}") unless uri.is_a?(URI::HTTP)
      uri.path = '/' if uri.path == ''
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
      http = Net::HTTP.new(uri.host, uri.port)

      if uri.port == 443
        http.use_ssl = true
        http.verify_mode = opts[:verify_ssl] === false ? OpenSSL::SSL::VERIFY_NONE : OpenSSL::SSL::VERIFY_PEER
      end

      [:open_timeout, :read_timeout, :ssl_version, :ciphers].each do |key|
        http.send("#{key}=", opts[key]) if opts.has_key?(key)
      end

      new(http)
    end

    def initialize(http)
      @http = http
    end

    def get(uri, opts = {})
      opts[:follow] = 10 if opts[:follow] == true

      path = uri[0] == '/' ? uri : Utils.parse_uri(uri).request_uri
      path.sub!(/\?.*|$/, '?' + Utils.encode(opts[:query])) if opts[:query]

      request = Net::HTTP::Get.new(path, DEFAULT_HEADERS.merge(opts[:headers] || {}))
      request.basic_auth(opts.delete(:username), opts.delete(:password)) if opts[:username]

      @resp, @data = @http.request(request)

      if REDIRECT_CODES.include?(@resp.code.to_i) && @resp['Location'] && (opts[:follow] && opts[:follow] > 0)
        opts[:follow] -= 1
        return get(@resp['Location'], nil, opts)
      end

      response
    end

    def request(method, uri, data, opts = {})
      return get(uri, opts.merge(query: data)) if method.to_s.downcase == 'get'

      uri     = Utils.parse_uri(uri)
      headers = DEFAULT_HEADERS.merge(opts[:headers] || {})

      query = if data.is_a?(String)
        data
      elsif opts[:json]
        Oj.dump(data) # convert to JSON
        headers['Content-Type'] = 'application/json'
      else # querystring, then
        Utils.encode(data)
      end

      if opts[:username] # opts[:password] is optional
        str = [opts[:username], opts[:password]].compact.join(':')
        headers['Authorization'] = "Basic " + Base64.encode64(str)
      end

      args = [method.to_s.downcase, uri.path, query, headers]
      args.delete_at(2) if args[0] == 'delete' # Net::HTTP's delete does not accept data

      @resp, @data = @http.send(*args)
      response
    end

    def response
      raise 'No response yet!' unless @resp
      @response ||= build_response(@resp, @data || @resp.body) # 1.8 vs 1.9 style responses
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
      uri = Utils.parse_uri(uri)
      opts.merge!(use_ssl: uri.scheme == 'https')
      opts.merge!(verify_mode: OpenSSL::SSL::VERIFY_NONE) if opts[:verify_ssl] === false

      Net::HTTP.start(uri.host, uri.port, opts) do |http|
        client = Client.new(http)
        # yield(client)
        client.instance_eval(&block)
      end
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
