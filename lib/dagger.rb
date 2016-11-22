# Dagger.
require 'dagger/version'
require 'dagger/response'
require 'dagger/parsers'

require 'net/https'
require 'base64'

module Dagger

  REDIRECT_CODES  = [301, 302, 303].freeze
  DEFAULT_HEADERS = {
    'Accept' => '*/*',
    'User-Agent' => "Dagger/#{VERSION} (Ruby Net::HTTP Wrapper, like curl)"
  }

  def self.get(uri, query = nil, opts = {})
    opts[:follow] = 10 if opts[:follow] == true

    uri       = parse_uri(uri)
    uri.query = encode(query) if query
    http      = client(uri, opts)
    request   = Net::HTTP::Get.new(uri.request_uri, DEFAULT_HEADERS.merge(opts[:headers] || {}))

    if opts[:username] # && opts[:password]
      request.basic_auth(opts.delete(:username), opts.delete(:password))
    end

    resp, data = http.request(request)

    if REDIRECT_CODES.include?(resp.code.to_i) && resp['Location'] && (opts[:follow] && opts[:follow] > 0)
      opts[:follow] -= 1
      return get(resp['Location'], nil, opts)
    end

    build_response(resp, data || resp.body) # 1.8 vs 1.9 style responses
  end

  def self.post(uri, params = {}, options = {})
    send_request('post', uri, params, options)
  end

  def self.put(uri, params = {}, options = {})
    send_request('put', uri, params, options)
  end

  def self.delete(uri, params = {}, options = {})
    send_request('delete', uri, params, options)
  end

  def self.request(method, url, params = {}, options = {})
    return get(url, params, options) if method.to_s.downcase == 'get'
    send_request(method.to_s.downcase, url, params, options)
  end

  private

  def self.send_request(method, uri, params, opts = {})
    uri     = parse_uri(uri)
    headers = opts[:headers] || {}

    query = if params.is_a?(String)
      params
    elsif opts[:json]
      Oj.dump(params) # convert to JSON
      headers['Content-Type'] = 'application/json'
    else
      encode(params)
    end

    if opts[:username] # opts[:password] is optional
      str = [opts[:username], opts[:password]].compact.join(':')
      headers['Authorization'] = "Basic " + Base64.encode64(str)
    end

    args = [method, uri.path, query, headers]
    args.delete_at(2) if method.to_s == 'delete' # Net::HTTP's delete does not accept data

    resp, data = client(uri, opts).send(*args)
    build_response(resp, data || resp.body) # 1.8 vs 1.9 style responses
  end

  def self.build_response(resp, body)
    resp.extend(Response)
    resp.set_body(body) unless resp.body
    resp
  end

  def self.client(uri, opts = {})
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = opts[:open_timeout] if opts[:open_timeout]
    http.read_timeout = opts[:read_timeout] if opts[:read_timeout]
    http.use_ssl = true if uri.port == 443
    http.verify_mode = opts[:verify_ssl] === false ? OpenSSL::SSL::VERIFY_NONE : OpenSSL::SSL::VERIFY_PEER
    http
  end

  def self.parse_uri(uri)
    uri = 'http://' + uri unless uri.to_s['http']
    uri = URI.parse(uri)
    raise ArgumentError.new("Invalid URI: #{uri}") unless uri.is_a?(URI::HTTP)
    uri.path = '/' if uri.path == ''
    uri
  end

  def self.encode(value, key = nil)
    case value
    when Hash  then value.map { |k,v| encode(v, append_key(key,k)) }.join('&')
    when Array then value.map { |v| encode(v, "#{key}[]") }.join('&')
    when nil   then ''
    else
      "#{key}=#{URI.escape(value.to_s)}"
    end
  end

  def self.append_key(root_key, key)
    root_key.nil? ? key : "#{root_key}[#{key.to_s}]"
  end

end
