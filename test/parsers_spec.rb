require './lib/dagger'

require 'rspec/mocks'
require 'rspec/expectations'

describe 'Parsers' do

  def send_request
    Dagger.get('http://foobar.com/test')
  end

  let(:fake_http) { double('Net::HTTP') }
  let(:fake_resp) { double('Net::HTTPResponse', code: 200) }

  before do
    allow(Net::HTTP).to receive(:new).and_return(fake_http)
    allow(fake_http).to receive(:verify_mode=).and_return(true)
    allow(fake_http).to receive(:request).and_return(fake_resp)
  end

  describe 'json' do
    before do
      allow(fake_resp).to receive(:content_type).and_return('application/json')
    end

    describe 'non matching content-type' do
      before do
        allow(fake_resp).to receive(:content_type).and_return('text/html')
        allow(fake_resp).to receive(:body).and_return('foo')
      end

      it 'returns nil' do
        expect(send_request.data).to eql(nil)
      end
    end

    describe 'empty data' do
      before do
        allow(fake_resp).to receive(:body).and_return('')
      end

      it 'returns nil' do
        expect(send_request.data).to eql(nil)
      end
    end

    describe 'invalid data' do
      before do
        allow(fake_resp).to receive(:body).and_return('abcdef')
      end

      it 'returns nil' do
        expect(send_request.data).to eql(nil)
      end
    end

    describe 'valid data' do
      before do
        allow(fake_resp).to receive(:body).and_return('{"foo":123}')
      end

      it 'returns nil' do
        expect(send_request.data).to eql({'foo' => 123})
      end
    end

  end

  describe 'XML' do
    before do
      allow(fake_resp).to receive(:content_type).and_return('text/xml')
    end

    describe 'empty data' do
      before do
        allow(fake_resp).to receive(:body).and_return('')
      end

      it 'returns nil' do
        expect(send_request.data).to eql(nil)
      end
    end

    describe 'invalid data' do
      before do
        allow(fake_resp).to receive(:body).and_return('abcdef')
      end

      it 'returns nil' do
        expect(send_request.data).to eql(nil)
      end
    end

    describe 'valid data' do
      before do
        allow(fake_resp).to receive(:body).and_return('<xml><foo>123</foo></xml>')
      end

      it 'returns nil' do
        res = send_request.data
        expect(res).to be_a(Ox::Element)
        expect(res.foo).to be_a(Ox::Element)
        expect(res.foo.text).to eql('123')
      end
    end

  end
end
