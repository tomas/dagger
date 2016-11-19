require './lib/dagger'

require 'rspec/mocks'
require 'rspec/expectations'

describe 'Requests' do

  describe '.get' do

    def send_request(url)
      Dagger.get(url)
    end

    describe 'empty url' do
      
      it 'raises error' do
        expect { send_request('') }.to raise_error(ArgumentError)
      end

    end

    describe 'invalid URL' do
      
      it 'raises error' do
        expect { send_request('asd123.rewqw') }.to raise_error(SocketError)
      end

    end

    describe 'nonexisting host' do
      
      it 'raises error' do
        expect { send_request('http://www.foobar1234567890foobar.com/hello') }.to raise_error(SocketError) 
      end

    end

    describe 'valid host' do
      
      it 'works' do
        expect { send_request('http://www.google.com') }.not_to raise_error
      end

    end

  end

end