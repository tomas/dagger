require 'ox'

XMLNode = Struct.new(:name, :text, :attributes, :children) do
  def [](key)
    children.select { |node| node.name.to_s == key.to_s }.first
  end
end

class Ox::Document
  def to_hash
    nodes.first.to_hash
  end
end

class Ox::Element
  def to_hash
    children = nodes.map { |n| n.class == self.class ? n.to_hash : nil }.compact
    XMLNode.new(value, text, attributes, children)
  end
end
