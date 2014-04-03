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
    
    def content_type
      self['Content-Type']
    end
    
    alias_method :status, :code

    def to_s
      body.to_s
    end
    
    def to_a
      [code, headers, to_s]
    end
    
    def data
      @data ||= Parsers.new(self).process || body 
    end

  end

end