require './lib/dagger'

require 'rspec/mocks'
require 'rspec/expectations'

describe 'Persitent mode' do

  it 'works' do
    fake_client = double('Client')
    expect(Dagger::Client).to receive(:new).once.and_return(fake_client)
    expect(fake_client).to receive(:get).twice #.and_return(fake_resp)

    obj = Dagger.open('https://www.google.com') do
      get('/search?q=dagger+http+client')
      get('google.com/search?q=thank+you+ruby')
    end
  end

end