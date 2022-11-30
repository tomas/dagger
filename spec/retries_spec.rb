require './lib/dagger'

require 'rspec/mocks'
require 'rspec/expectations'

describe 'Retries' do

  def send_request
    Dagger.get('http://foobar.com/test', opts)
  end

  let(:fake_http) { double('Net::HTTP', started?: true, "keep_alive_timeout=": true, "open_timeout=": true, "read_timeout=": true) }
  let(:fake_resp) { double('Net::HTTPResponse', code: 200, body: 'foo') }

  before do
    allow(Net::HTTP).to receive(:new).at_least(:once).and_return(fake_http)
    allow(fake_http).to receive(:verify_mode=).and_return(true)
  end

  describe 'on ECONNREFUSED' do

    context 'if no retries option passed' do

      let(:opts) { {} }

      it 'does not retry request, and raises error' do
        expect(fake_http).to receive(:request).once.and_raise(Errno::ECONNREFUSED)
        expect { send_request }.to raise_error(Errno::ECONNREFUSED)
      end

    end

    context 'if retries is 1' do

      let(:opts) { { retries: 1, retry_wait: 1 } }

      context 'and it still fails' do

        it 'sends a second request, and raises error' do
          expect(fake_http).to receive(:request).twice.and_raise(Errno::ECONNREFUSED)
          expect { send_request }.to raise_error(Errno::ECONNREFUSED)
        end

      end

      context 'and then it works' do

        it 'sends a second request, and does not raise error' do
          expect(fake_http).to receive(:request).once.and_raise(Errno::ECONNREFUSED)
          expect(fake_http).to receive(:request).once.and_return(fake_resp)
          allow(fake_resp).to receive(:[]).with('Content-Type').and_return('text/plain')

          expect(send_request.body).to eq('foo')
        end

      end

    end

  end
end
