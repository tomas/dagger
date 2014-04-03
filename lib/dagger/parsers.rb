require 'json'

class Parsers
  
  def initialize(response)
    @body = response.body
    @normalized = response.content_type.to_s.sub('/', '_')
  end
  
  def process
    send(@normalized, @body) if respond_to?(@normalized)
  end
  
  def application_json(body)
    JSON.parse(body)
  end
  
  alias_method :text_javascript, :application_json
  
end