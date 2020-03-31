require './lib/dagger'

require 'rspec/mocks'
require 'rspec/expectations'

describe 'IP Connection' do

  it 'works' do
    expect do
      Dagger.get('http://www.awiefjoawijfaowef.com')
    end.to raise_error(SocketError, /getaddrinfo/)

    resp = Dagger.get('http://www.awiefjoawijfaowef.com', { ip: '1.1.1.1'} )
    expect(resp.body).to match('<center>cloudflare</center>')
  end

end