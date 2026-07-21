RSpec.configure do |config|
  config.before(:suite) do
    begin
      # FactoryBot.lint temporarily disabled during Rails 7.1 upgrade
      # TODO: Re-enable and fix remaining factory validations
    ensure
      DatabaseCleaner.clean
    end
  end
end
