# Dagger

Featherweight wrapper around Net::HTTP. 

Follows redirects if instructed, and comes with out-of-the-box parsing of JSON and XML, via [oj](https://github.com/ohler55/oj) and [ox](https://github.com/ohler55/ox), respectively.

# Installation

In your Gemfile:

    gem 'dagger'

# Usage

## `get(url, [params], [options])`

```rb
require 'dagger'
resp = Dagger.get('http://google.com')

puts resp.body # => "<!doctype html...>"

# if query is passed, it is appended as a query string
Dagger.get('google.com/search', { q: 'dagger' }) # => requests '/search?q=dagger'
```

## `post(url, params, [options])`

```rb
resp = Dagger.post('http://api.server.com', { foo: 'bar' })
puts resp.status # => 200

# if you want to send JSON to the server, you can pass the { json: true } option,
# which converts your params object to JSON, and also sets Content-Type to 'application/json'
resp = Dagger.put('http://server.com', { foo: 'bar' }, { json: true })

# now, if the endpoint returned a parseable content-type (e.g. 'application/json')
# then `resp.data` will return the parsed result. `body` contains the raw data.
puts resp.data # => { result: 'GREAT SUCCESS!' }
```

Same syntax applies for `put`, `patch` and `delete` requests. 

## `request(method, url, [params], [options])`

```rb
resp = Dagger.request(:put, 'https://api.server.com', { foo: 'bar' }, { follow: 10 })
puts resp.headers # { 'Content-Type' => 'application/json', ... } 
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
