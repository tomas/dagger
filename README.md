# Dagger

Featherweight wrapper around Net::HTTP. 

Follows redirects if instructed, and comes with out-of-the-box parsing of JSON and XML, via [oj](https://github.com/ohler55/oj) and [ox](https://github.com/ohler55/ox), respectively.

# Installation

In your Gemfile:

    gem 'dagger'

# Usage

## `get(url, [options])`

```rb
require 'dagger'
resp = Dagger.get('http://google.com')

puts resp.body # => "<!doctype html...>"

# you can also pass a query via the options hash, in which case is appended as a query string.
Dagger.get('google.com/search', { query: { q: 'dagger' } }) # => requests '/search?q=dagger'
```

## `post(url, params, [options])`

```rb
resp = Dagger.post('http://api.server.com', { foo: 'bar' })
puts resp.code # => 200

# if you want to send JSON to the server, you can pass the { json: true } option,
# which converts your params object to JSON, and also sets Content-Type to 'application/json'
resp = Dagger.put('http://server.com', { foo: 'bar' }, { json: true })

# now, if the endpoint returned a parseable content-type (e.g. 'application/json')
# then `resp.data` will return the parsed result. `body` contains the raw bytes.
puts resp.data # => { result: 'GREAT SUCCESS!' }
```

Same syntax applies for `put`, `patch` and `delete` requests. 

## `request(method, url, [params], [options])`

```rb
resp = Dagger.request(:put, 'https://api.server.com', { foo: 'bar' }, { follow: 10 })
puts resp.headers # { 'Content-Type' => 'application/json', ... } 
```
In this case, if you want to include a query in your get request, simply pass it as 
the `params` argument.

## `open(url, [options]) # => &block`

Oh yes. Dagger can open and hold a persistent connection so you can perform various 
requests without the overhead of establishing new TCP sessions.

```rb
Dagger.open('https://api.server.com', { verify_ssl: 'false' }) do
   if post('/login', { email: 'foo@bar.com', pass: 'secret' }).success?
     resp = get('/something', { query: { items: 20 }, follow: 5 }) # follow 5 redirects max.
     File.open('something', 'wb') { |f| f.write(resp.body) }
   end
end
```

Passing the block is optional, by the way. You can also open and call the request verb on the returned object:

```rb
  http = Dagger.open('https://api.server.com')
  resp = http.get('/foo')
  puts resp.code # => 200
  resp = http.post('/bar', { some: 'thing' })
  puts resp.data.inspect # => { status: "success" }
  http.close # don't forget to!
```

# Options

These are all the available options.

```rb
opts = {
  json: true, # converts params object to JSON and sets Content-Type header. (POST/PUT/PATCH only)
  follow: true, # follow redirects (10 by default)
  headers: { 'Accept': 'text/xml' },
  username: 'dagger', # for HTTP auth
  password: 'fidelio', 
  verify_ssl: false, # true by default
  open_timeout: 30,
  read_timeout: 30
}
resp = Dagger.post('http://test.server.com', { payload: 1 }, opts)
```

# Credits

Written by Tomás Pollak.

# Copyright

(c) Fork, Ltd. MIT Licensed.
