require './lib/dagger'

require 'rspec/mocks'
require 'rspec/expectations'

describe 'sending data' do

  it 'works with get if using .request' do
    resp = Dagger.request('get', 'https://httpbingo.org/get?x=123', { foo: 'bar', testing: 1 }, { json: true })
    expect(resp.ok?).to eq(true)
  end

  it 'works with get if passing body as option' do
    resp = Dagger.get('https://httpbingo.org/get?x=123', { body: { foo: 'bar', testing: 1 }, json: true })
    expect(resp.ok?).to eq(true)
  end


end