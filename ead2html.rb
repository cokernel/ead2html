require "find"
require "mustache"
require "om"
require "trollop"

class Container
  attr_reader :label, :sortbit

  def initialize node
    if node
      @label = case node['type']
      when 'othertype'
        "#{node['label']} #{node.content.downcase}".gsub(/\ \ /, ' ').strip
      else
        "#{node['type']} #{node.content.downcase}".gsub(/\ \ /, ' ').strip
      end
      @sortbit = "00000"
      if node.content =~ /(\d+)/
        @sortbit = sprintf("%04d", $1.to_i) + " " + node.content
      end
    else
      @label = ''
      @sortbit = '00000'
    end
  end
end

class ContainerList
  attr_reader :title, :date, :label, :sortkey, :list

  def initialize node
    @title = "No title available"
    @date = ""
    Nokogiri::XML(node.parent.to_xml).xpath("//unittitle").each do |n|
      @title = n.content
    end
    Nokogiri::XML(node.parent.to_xml).xpath("//unitdate").each do |n|
      @date = n.content
    end
    @list = [Container.new(node)]
    node.parent.children.each do |n|
      if n['parent'] == node['id']
        @list << Container.new(n)
      end
    end
    @label = @list.collect {|item| item.label}.join(', ')
    @sortkey = @list.collect {|item| item.sortbit}.join(', ')
  end

  def count
    @list.count
  end

  def add container
    @list << container
    @label = @list.collect {|item| item.label}.join(', ')
    @sortkey = @list.collect {|item| item.sortbit}.join(', ')
  end
end

class EadMetadata
  include OM::XML::Document

  set_terminology do |t|
    t.root(path: "ead", xmlns: "urn:isbn:1-931666-22-9", schema: "urn:isbn:1-931666-22-9 http://www.loc.gov/ead/ead.xsd", "xmlns:ns2" => "http://www.w3.org/1999/xlink", "xmlns:xsi" => "http://www.w3.org/2001/XMLSchema-instance")
    t.titleproper
    t.container
  end

  def scan_containers
    h = {
      title: self.titleproper.first.strip,
      nodes: [],
    }
    self.container.nodeset.each do |node|
      if node.has_attribute? 'id'
        h[:nodes] << ContainerList.new(node)
      end
    end
    h[:nodes].sort! do |a, b|
      a.sortkey <=> b.sortkey
    end
    max = 0
    
    # pad
    h[:nodes].each do |n|
      if n.count > max
        max = n.count
      end
    end

    h[:nodes].each_with_index do |n, i|
      shortfall = max - n.count
      (1..shortfall).each do |k|
        n.add(Container.new(nil))
      end
    end

    h
  end

  def self.xml_template
    Nokogiri::XML.parse("<ead/>")
  end
end

if __FILE__ == $0
  opts = Trollop::options do
    opt :input, "EAD file to read", :type => :string
    opt :output, "HTML file to write", :type => :string
  end

  if opts[:input_given] and opts[:output_given]
    input = IO.read(opts[:input])
    template = IO.read(File.join(File.dirname(__FILE__), 'templates', 'ead.mustache'))
    metadata = EadMetadata.from_xml(input).scan_containers
    File.open(opts[:output], "w") do |output|
      output.write Mustache.render(template, metadata)
    end
  end
end
