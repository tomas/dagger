require 'oj'
require 'ox'
require 'dagger/ox_extension'

class Parsers

  def initialize(response)
    if type = response.content_type
      @normalized_type = response.content_type.split(';').first.gsub(/[^a-z]/, '_')
      @body = response.body
    end
  end

  def process
    send(@normalized_type, @body) if @normalized_type && respond_to?(@normalized_type)
  end

  def application_json(body)
    Oj.load(body)
  rescue Oj::ParseError
    nil
  end

  alias_method :text_javascript, :application_json
  alias_method :application_x_javascript, :application_json

  def text_xml(body)
    if res = Ox.parse(body)
      res.to_hash
    end
  rescue Ox::ParseError
    nil
  end

  alias_method :application_xml, :text_xml

end