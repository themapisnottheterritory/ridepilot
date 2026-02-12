# Ruby 3.0 removed URI.escape and URI.encode
# Paperclip and other older gems still use these methods
# This monkey patch restores them for compatibility

module URI
  def self.escape(str)
    parser.escape(str.to_s)
  end

  def self.encode(str)
    parser.escape(str.to_s)
  end

  def self.parser
    @parser ||= URI::RFC2396_Parser.new
  end
end
