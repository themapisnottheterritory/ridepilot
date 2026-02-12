begin
  require 'paranoia'
rescue LoadError => e
  # Paranoia gem not available, create a stub
  module Paranoia
    def acts_as_paranoid(options = {})
      # Stub implementation
      puts "Warning: acts_as_paranoid called but Paranoia gem not loaded"
    end
  end
  
  # Add the method to ActiveRecord::Base
  ActiveRecord::Base.extend Paranoia
end