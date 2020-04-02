require './lib/dagger'

require 'rspec/mocks'
require 'rspec/expectations'

describe 'Persistent mode' do

  it 'works' do
    fake_client = double('Client')
    expect(Dagger::Client).to receive(:new).once.and_return(fake_client)
    expect(fake_client).to receive(:open).once #.and_return(fake_resp)
    expect(fake_client).to receive(:close).once #.and_return(fake_resp)

    obj = Dagger.open('https://www.google.com') do
      get('/search?q=dagger+http+client')
      get('google.com/search?q=thank+you+ruby')
    end
  end

end

describe 'using threads' do

  def get(url)
    @http.get(url)
  end

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
          puts "Fetching #{url}"
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