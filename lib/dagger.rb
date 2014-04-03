# Dagger.
# Simple Net::HTTP wrapper (in less than 100 LOC)
# Written by Tomas Pollak

# Example Usage ---------------------------------
#
# resp, body = Dagger.get('http://google.com')
# puts body if resp.code == 200
#
# opts = { username: 'foobar', password: 'secret' }
# resp, body = Dagger.get('http://api.server.com', opts)
#
# opts = { verify_ssl: false, open_timeout: 30 }
# resp, body = Dagger.post('http://twitter.com', { foo: 'bar' }, opts)

require 'dagger/version'
require 'dagger/response'
require 'dagger/parsers'

require 'net/https'
require 'base64'

module Dagger
  
  DEFAULT_HEADERS = {
    'User-Agent' => "Dagger/#{VERSION} (Ruby Net::HTTP Wrapper, like curl)" 
  }
  
  def self.get(uri, query = nil, opts = {})
    raise ArgumentError.new("Empty URL!") if (uri || '').strip == ''

    opts[:follow] = 10 if opts[:follow] == true
    uri = parse_uri(uri)
    uri.query = encode(opts[:query]) if opts[:query]

    http = client(uri, opts)
    request = Net::HTTP::Get.new(uri.request_uri, DEFAULT_HEADERS.merge(opts[:headers] || {}))

    if opts[:username] && opts[:password]
      request.basic_auth(opts.delete(:username), opts.delete(:password))
    end

    resp, data = http.request(request)

    if [301,302].include?(resp.code.to_i) && resp['Location'] && (opts[:follow] && opts[:follow] > 0)
      opts[:follow] -= 1
      return get(resp['Location'], nil, opts)
    end
      
    build_response(resp, data || resp.body) # 1.8 vs 1.9 style responses 
  end

  def self.post(uri, params = {}, options = {})
    request('post', uri, params, options)
  end

  def self.put(uri, params = {}, options = {})
    request('put', uri, params, options)
  end

  def self.delete(uri, params = {}, options = {})
    request('delete', uri, params, options)
  end

  def self.request(method, url, params = {}, options = {})
    return get(url, options) if method.to_s.downcase == 'get'
    request(method.to_s.downcase, url, params, options)
  end

  private

  def self.request(method, uri, params, opts = {})
    # raise "Params should be a hash." unless params.is_a?(Hash)
    uri = parse_uri(uri)
    query = params.is_a?(String) ? params : encode(params)

    headers = opts[:headers] || {}

    if opts[:username] && opts[:password]
      headers['Authorization'] = "Basic " + Base64.encode64("#{opts[:username]}:#{opts[:password]}")
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
    http.verify_mode = opts[:verify_ssl] ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
    http
  end
  
  def self.parse_uri(uri)
    uri = 'http://' + uri unless uri.to_s['http']
    uri = URI.parse(uri)
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
