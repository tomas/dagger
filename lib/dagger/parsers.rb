require 'oj'
require 'ox'
require 'dagger/ox_extension'

class Parsers

  def initialize(response)
    @body = response.body
    @normalized = response.content_type.to_s.sub('/', '_').split(';').first
  end

  def process
    send(@normalized, @body) if respond_to?(@normalized)
  end

  def application_json(body)
    Oj.load(body)
  rescue Oj::ParseError
    nil
  end

  alias_method :text_javascript, :application_json

  def text_xml(body)
    Ox.parse(body)
  rescue Ox::ParseError
    nil
  end

  alias_method :application_xml, :text_xml

end