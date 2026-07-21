begin
  require 'simple_token_authentication'
rescue LoadError => e
  # SimpleTokenAuthentication gem not available, create a stub
  module TokenAuthenticatable
    def acts_as_token_authenticatable(options = {})
      # Stub implementation
      puts "Warning: acts_as_token_authenticatable called but simple_token_authentication gem not loaded"
    end
  end
  
  # Add the method to ActiveRecord::Base
  ActiveRecord::Base.extend TokenAuthenticatable
  
  # Create a stub module for TokenAuthenticationHelpers
  module TokenAuthenticationHelpers
    # Empty implementation
  end
end