# Ruby 3.2 compatibility: require logger before Rails
# Logger was extracted from stdlib in Ruby 3.1+
require 'logger'

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.
