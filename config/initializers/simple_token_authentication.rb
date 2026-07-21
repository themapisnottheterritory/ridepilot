begin
  require 'simple_token_authentication'

  SimpleTokenAuthentication.configure do |config|
    # Configure the session persistence policy after a successful sign in,
    # in other words, if the authentication token acts as a signin token.
    # If true, user is stored in the session and the authentication token and
    # email may be provided only once.
    # If false, users must provide their authentication token and email at every request.
    config.sign_in_token = false

    # Configure the name of the HTTP headers watched for authentication.
    config.header_names = { user: { authentication_token: 'X-User-Token', username: 'X-User-Username' } }

    # Configure the name of the attribute used to identify the user for authentication.
    # That attribute must exist in your model.
    config.identifiers = { user: 'username' }
  end
rescue LoadError => e
  # SimpleTokenAuthentication not available
  puts "SimpleTokenAuthentication not available: #{e.message}"
end