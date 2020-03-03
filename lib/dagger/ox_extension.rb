require 'ox'

XMLNode = Struct.new(:name, :text, :attributes, :children) do

  alias_method :to_s, :text
  alias_method :value, :text

  def count
    raise "Please call #children.count"
  end

  def to_hash
    self # for backwards compat
  end

  # this lets us traverse an parsed object like this:
  # doc[:child][:grandchild].value
  def [](key)
    found = children.select { |node| node.name.to_s == key.to_s }
    found.empty? ? nil : found.size == 1 ? found.first : found
  end

  def slice(*arr)
    Array(arr).flatten.map { |key| self[key] }
  end

  def values(arr = nil, include_empty: false)
    if arr
      Array(arr).flatten.each_with_object({}) do |key, memo| 
        if found = self[key] and (found.to_s || include_empty)
          memo[key] = found.to_s
        end
      end
    else
      children.each_with_object({}) do |child, memo| 
        if child.to_s || include_empty
          memo[child.name] = child.to_s
        end
      end
    end
  end

  def dig(*paths)
    list = Array(paths).flatten
    res = list.reduce([self]) do |parents, key|

      if parents
        found = parents.map do |parent|
          parent.children.select { |node| node.name.to_s == key.to_s }
        end.flatten

        found.any? ? found : nil
      end
    end

    res.nil? || res.empty? ? nil : res.size == 1 ? res.first : res
  end

  # returns first matching node
  def first(key)
    if found = self[key]
      found.is_a?(XMLNode) ? found : found.first
    else
      children.find do |ch|
        if res = ch.first(key)
          return res
        end
      end
    end
  end

  # returns all matching nodes
  def all(key)
    found    = self[key]
    direct   = found.is_a?(XMLNode) ? [found] : found || []
    indirect = children.map { |ch| ch.all(key) }.flatten.compact
    direct + indirect
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
