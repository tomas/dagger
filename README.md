# Dagger

Very simple wrapper around Net::HTTP.

# Installation

In your Gemfile:

    gem 'dagger'

# Usage

## `get(url)`

```rb
require 'dagger'
resp = Dagger.get('http://google.com')

puts resp.body # => "<!doctype html...>"
```

## `post(url, data)`

```rb
resp = Dagger.post('http://api.server.com', { foo: 'bar' })
puts resp.status # => 200

# if the endpoint returned a parseable content-type (e.g. 'application/json')
# then `resp.data` will return the parsed result. `body` contains the raw data.
puts resp.data # => { result: 'GREAT SUCCESS!' }
```

Same syntax applies for `put`, `patch` and `delete` requests. You can also pass options as the third param:

```rb
opts = {
  follow: true, # follow redirects (10 by default)
  headers: { 'Accept': 'text/xml' },
  username: 'dagger', # for HTTP auth
  password: 'fidelio', 
  open_timeout: 30,
  read_timeout: 30
}
resp = Dagger.post('http://test.server.com', { payload: 1 }, opts)
```

# Credits

Written by Tomás Pollak.

# Copyright

(c) Fork, Ltd. MIT Licensed.
