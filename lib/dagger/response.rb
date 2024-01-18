module Dagger

  module Response

    attr_reader :body

    def self.extended(base)
      # puts base.inspect
    end

    def set_body(string)
      raise "Body is set!" if body
      @body = string
    end

    def headers
      to_hash # from Net::HTTPHeader module
    end

    def code
      super.to_i
    end

    alias_method :status, :code

    def content_type
      self['Content-Type']
    end

    def success?
      [200, 201].include?(code)
    end

    alias_method :ok?, :success?

    def redirect?
      [301, 302, 303, 307, 308].include?(code)
    end

    def to_s
      body.to_s
    end

    def to_a
      [code, headers, to_s]
    end

    def data
      @data ||= Parsers.new(self).process
    end

  end

end