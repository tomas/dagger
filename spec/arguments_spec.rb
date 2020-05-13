require './lib/dagger'

require 'rspec/mocks'
require 'rspec/expectations'

describe 'arguments' do

  describe 'URL' do

    def send_request(url)
      Dagger.get(url)
    end

    describe 'empty url' do

      it 'raises error' do
        # expect { send_request('') }.to raise_error(URI::InvalidURIError)
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

    describe 'host without protocol' do

      it 'works' do
        expect(send_request('www.google.com')).to be_a(Net::HTTPResponse)
      end

    end


    describe 'valid host' do

      it 'works' do
        expect(send_request('http://www.google.com')).to be_a(Net::HTTPResponse)
      end

    end

  end

end
