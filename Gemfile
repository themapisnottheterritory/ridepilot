source 'https://rubygems.org'

#ruby '2.4.5'
#ruby '2.7.8'
#ruby '3.0.7'
#ruby '3.1.6'
#ruby '3.2.6'
ruby '3.2.9'

git_source(:github) do |repo_name|
  repo_name = "#{repo_name}/#{repo_name}" unless repo_name.include?("/")
  "https://github.com/#{repo_name}.git"
end

### DEFAULT RAILS GEMS ####################

# Rails 7.1 LTS with Ruby 3.2 support
gem 'rails', '~> 7.1.5'
gem 'zeitwerk', '~> 2.6'
gem 'i18n', '~> 1.14'

# Use SCSS for stylesheets
gem 'sass-rails'
# Use Uglifier as compressor for JavaScript assets
gem 'uglifier'
# Use CoffeeScript for .js.coffee assets and views
gem 'coffee-rails'
# See https://github.com/sstephenson/execjs#readme for more supported runtimes
# Use Node.js as JS runtime (already installed in Docker container) for Ruby 3.x compatibility
# gem 'mini_racer',  platforms: :ruby
# Use jquery as the JavaScript library
gem 'jquery-rails'
# Turbolinks makes following links in your web application faster. Read more: https://github.com/rails/turbolinks
#gem 'turbolinks'
# Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder
# gem 'jbuilder', '~> 2.0'
# A set of Rails responders to dry up your application
gem 'responders', '~> 3.0'
# Use PostgreSQL as db for activerecord
gem 'pg'
gem 'mysql2', '~> 0.5'  # For direct AVL GPS reads from busavl MySQL database
gem 'concurrent-ruby', '1.3.5'

### UI ####################################

#begin pz 3/10/25
#gem 'pp', '~> 0.2.0'
gem 'nokogiri', '>= 1.12'
gem 'loofah', '>= 2.22'
gem 'ffi', '1.17.1', platforms: [:ruby]
#end pz 3/10/25


# view partial template
gem 'haml'
# bootstrap
gem 'bootstrap-sass'
# needed for trip address picker
gem 'twitter-typeahead-rails', github: 'camsys/twitter-typeahead-rails'
gem 'handlebars_assets'
# jquery autocomplete
gem 'rails-jquery-autocomplete'
# view pagination
gem 'will_paginate'
# html datatables
gem 'jquery-datatables-rails'
# font-awesome icons
gem "font-awesome-rails"
# overcome IE9 4096 per stylesheet limit
# DISABLED: No longer needed for modern browsers, incompatible with Rails 7.1
# gem 'css_splitter'
# Form helper for accepts_nested_attributes_for
gem 'nested_form'
# styling
gem 'bootstrap-kaminari-views'
# momentjs for datetime parsing
gem 'momentjs-rails'
# phone number validation and display
gem 'phony_rails'
# Printing
gem 'wicked_pdf'
# In-line editing
gem 'bootstrap-editable-rails'

### USER AUTH ##############################

gem 'cancancan'
gem 'devise'
gem 'devise_account_expireable'
gem 'devise-security'
# Office 365 / Entra ID SSO (Phase 1 — dark). The strategy only activates when
# entra_id credentials are configured; password login remains the fallback.
gem 'omniauth-entra-id'
gem 'omniauth-rails_csrf_protection'
#gem 'devise_security_extension', github: 'camsys/devise_security_extension'
#gem 'devise_security_extension', path: '~/devise_security_extension'

### API ##############################
# Rack Middleware for handling Cross-Origin Resource Sharing (CORS), which makes cross-origin AJAX possible.
gem 'rack-cors', :require => 'rack/cors'
# Token authentication
gem 'simple_token_authentication', '~> 1.0'
# API serializer (for driver app & CAD/AVL API responses)
gem 'fast_jsonapi', '~> 1.5'

### GEOSPATIAL ##############################

gem 'rgeo'
gem "rgeo-proj4"
# Updated for Rails 7.1 compatibility
gem 'activerecord-postgis-adapter', '~> 9.0'

### FILE UPLOAD #############################

gem 'paperclip'
gem 'fog-aws'
gem 'remotipart' # allows remote multipart (file upload) forms
gem 'aws-sdk-s3', '~> 1'

### CAMSYS ENGINES ###########################
# NOTE: Using local forks with relaxed Rails version constraints
# Gemspecs updated to allow Rails >= 5.0, < 8

# reporting engine
gem 'reporting', path: '../engines/reporting'
gem 'translation_engine', path: '../engines/translation_engine'
# ridepilot_cad_avl engine dissolved — code migrated into main app (controllers, serializers, views)

### OTHERS ##################################

# Manage app-specific cron tasks using a Ruby DSL, see config/schedule.rb
gem 'whenever', :require => false
# RADAR current version is 0.13.0, but schedule_atts requires > 0.7.0
gem 'ice_cube', '~> 0.6.8'
# Date and time validation plugin for ActiveModel and Rails
gem 'validates_timeliness', '~> 7.0'
# Adds the ability to normalize attributes cleanly with code blocks and predefined normalizers
gem 'attribute_normalizer'
# For change tracking and auditing
gem 'paper_trail'
# ENV var management
gem 'figaro'
# soft-delete
gem "paranoia"
# logging activities for Tracker Action Log
gem 'public_activity' 
# Manage application-level settings
gem 'rails-settings-cached'
# background worker - updated for Rails 7.1 compatibility
gem 'sidekiq', '~> 7.0'
# Use redis as the cache_store for Rails
gem 'redis-rails'
# Excel
gem 'rubyXL'
# Data migration
gem 'data_migrate'
# SMS notifications via Twilio
gem 'twilio-ruby', '~> 7.0'

group :production do
  gem 'exception_notification'
end

group :integration, :qa, :production do 
  gem 'rails_12factor'
  gem 'unicorn'
  gem 'rack-timeout'
  gem 'wkhtmltopdf-binary'
end

group :test, :development do
  gem 'byebug'
  gem 'rspec-rails'
  gem 'rails-controller-testing'
  gem 'capybara'
  gem 'factory_bot_rails'
  gem 'database_cleaner'
  gem 'faker'
  gem 'timecop'
end

group :development do
  gem 'puma', '~> 3.7'
  # preview mail in dev
  gem "letter_opener"
  # File watching for reloading in development
  gem 'listen', '~> 3.3'
  # Spring speeds up development by keeping your application running in the background. Read more: https://github.com/rails/spring
  #gem 'spring'
  #gem "spring-commands-rspec"
  gem 'better_errors'
  gem 'binding_of_caller'
  gem 'web-console', '~> 4.0'
end

group :test do 
  gem 'launchy'
  gem 'selenium-webdriver'
end

group :doc do
  # bundle exec rake doc:rails generates the API under doc/api.
  gem 'sdoc'
end
