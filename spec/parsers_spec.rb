require './lib/dagger'

require 'rspec/mocks'
require 'rspec/expectations'

describe 'Parsers' do

  def send_request
    Dagger.post('http://foobar.com/test', { foo: 'bar'})
  end

  let(:fake_http) { double('Net::HTTP', started?: true) }
  let(:fake_resp) { double('Net::HTTPResponse', code: 200) }

  before do
    allow(Net::HTTP).to receive(:new).and_return(fake_http)
    allow(fake_http).to receive(:keep_alive_timeout=).and_return(true)
    allow(fake_http).to receive(:read_timeout=).and_return(true)
    allow(fake_http).to receive(:open_timeout=).and_return(true)
    allow(fake_http).to receive(:verify_mode=).and_return(true)
    allow(fake_http).to receive(:post).and_return(fake_resp)
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
        allow(fake_resp).to receive(:body).and_return('<xml><foo>123</foo><bar><test>456</test></bar></xml>')
      end

      it 'returns XMLNode obj' do
        res = send_request.data
        expect(res).to be_a(XMLNode)
        expect(res.to_node).to eql(res)
        expect(res['foo']).to be_a(XMLNode)
        expect(res['foo'].text).to eql('123')

        # test dig behaviour
        expect(res.dig('xxx', 'test', '111')).to be(nil)
        expect(res.dig('bar', 'test')).to be_a(XMLNode)
        expect(res.dig('bar', 'test').to_s).to eql('456')
      end
    end

    describe 'XMLNode extension' do

      xml = %(
        <xml>
          <foo attr="bar">test</foo>
          <nested>
            <item>
              <title attr="downcased">foobar</title>
            </item>
          </nested>
        </xml>
      )

      it 'works' do
        doc = Ox.parse(xml)
        obj = doc.to_node

        expect(obj[:nested][:item][:title].text).to eql('foobar')
      end

    end

  end
end
