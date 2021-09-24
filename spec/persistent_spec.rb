require './lib/dagger'

require 'rspec/mocks'
require 'rspec/expectations'

describe 'Persistent mode' do

  it 'works' do
    # fake_client = double('Client')
    # expect(Dagger::Client).to receive(:new).once.and_return(fake_client)
    # expect(fake_client).to receive(:open).once #.and_return(fake_resp)
    # expect(fake_client).to receive(:close).once #.and_return(fake_resp)

    res1, res2 = nil, nil
    obj = Dagger.open('https://www.google.com') do
      res1 = get('/search?q=dagger+http+client', { body: 'foo' })
      res2 = get('https://www.google.com/search?q=thank+you+ruby')
      res3 = post('https://www.google.com/search?q=foobar', { foo: 'bar' })
    end

    expect(res1.code).to eq(400)
    expect(res2.code).to eq(200)
    expect(res2.code).to eq(200)
    expect(obj).to be_a(Dagger::Client)
  end

end

describe 'using threads' do

  def connect(host)
    raise if @http
    @http = Dagger.open(host)
  end

  def disconnect
    raise if @http.nil?
    @http.close
    @http = nil
  end

  it 'works' do
    thread_count = 10
    urls_count = 100
    host = 'https://postman-echo.com'
    urls = urls_count.times.map { |i| "/get?page/#{i}" }
    result = []

    mutex = Mutex.new
    thread_count.times.map do
      Thread.new(urls, result) do |urls, result|
        # mutex.synchronize { Dagger.open(host) }
        http = Dagger.open(host)
        while url = mutex.synchronize { urls.pop }
          # puts "Fetching #{url}"
          resp = http.get(url)
          mutex.synchronize do
            result.push(resp.code)
          end
        end
        # mutex.synchronize { http.close }
        http.close
      end
    end.each(&:join)

    expect(result.count).to eq(urls_count)
  end

end