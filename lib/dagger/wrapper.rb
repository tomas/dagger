require_relative '../dagger'

module Dagger

  module Wrapper

    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def base_url(str = nil)
        if str # set
          @base_url = str
        else
          @base_url or raise "base_url unset!" # get
        end
      end

      def base_options(opts = nil)
        if opts # set
          @base_options = opts
        else
          @base_options or raise "base_url unset!" # get
        end
      end
    end

    def initialize(opts = {})
      @logger = opts.delete(:logger)
      @options = opts
    end

    def get(path, params = {}, opts = {})
      request(:get, path, params, opts)
    end

    def post(path, params = {}, opts = {})
      request(:post, path, params, opts)
    end

    def put(path, params = {}, opts = {})
      request(:put, path, params, opts)
    end

    def patch(path, params = {}, opts = {})
      request(:patch, path, params, opts)
    end

    def delete(path, params = {}, opts = {})
      request(:delete, path, params, opts)
    end

    def request(method, path, params = {}, opts = nil)
      url = self.class.base_url + path
      resp = benchmark("#{method} #{path}") do
        http.request(method, url, params, base_options.merge(opts))
      end

      handle_response(resp, method, path, params)
    end

    def connect(&block)
      open_http
      if block_given?
        yield
        close_http
      else
        at_exit { close_http }
      end
    end

    def disconnect
      close_http
    end

    private
    attr_reader :options

    def handle_response(resp, method, path, params)
      resp
    end

    def base_options
      {}
    end

    def request_options
      self.class.base_options.merge(base_options)
    end

    def benchmark(message, &block)
      log(message)
      start = Time.now
      resp = yield
      time = Time.now - start
      log("Got response in #{time.round(2)} secs")
      resp
    end

    def log(str)
      logger.info(str)
    end

    def logger
      @logger ||= begin
        require 'logger'
        Logger.new(@options[:logfile])
      end
    end

    def http
      @http || Dagger
    end

    def open_http
      raise "Already open!" if @http
      @http = Dagger.open(self.class.base_url)
    end

    def close_http
      @http.close if @http
      @http = nil
    end

    # def wrap(hash)
    #   Entity.new(hash)
    # end

    # class Entity
    #   def initialize(props)
    #     @props = props
    #   end

    #   def get(prop)
    #     val = @props[name.to_s]
    #   end

    #   def method_missing(name, args, &block)
    #     if @props.key?(name.to_s)
    #       get(name)
    #     else
    #       # raise NoMethodError, "undefined method #{name}"
    #       super
    #     end
    #   end
    # end

  end

end