require 'ox'

XMLNode = Struct.new(:name, :text, :attributes, :children) do

  alias_method :to_s, :text
  alias_method :value, :text

  def to_node
    self
  end

  def count
    raise "Please call #children.count"
  end

  def keys
    @keys ||= children.collect(&:name)
  end

  def is_array?
    keys.count != keys.uniq.count
  end

  # this lets us traverse an parsed object like this:
  # doc[:child][:grandchild].value
  def [](key)
    found = children.select { |node| node.name.to_s == key.to_s }
    found.empty? ? nil : found.size == 1 ? found.first : found
  end

  # returns list of XMLNodes with matching names
  def slice(*arr)
    Array(arr).flatten.map { |key| self[key] }
  end

  def values(keys_arr = nil, include_empty: false)
    if keys_arr
      Array(keys_arr).flatten.each_with_object({}) do |key, memo|
        if found = self[key] and (found.to_s || include_empty)
          memo[key] = found.to_s
        end
      end
    elsif is_array?
      children.map(&:values)
    else
      children.each_with_object({}) do |child, memo|
        memo[child.name] = child.children.any? ? child.values : child.text
      end
    end
  end

  alias_method :to_hash, :values
  alias_method :to_h, :values

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
  def to_node
    nodes.first.to_node
  end
end

class Ox::Element
  def to_node
    children = nodes.map { |n| n.class == self.class ? n.to_node : nil }.compact
    XMLNode.new(value, text, attributes, children)
  end
end
