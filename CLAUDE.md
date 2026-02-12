# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands
- Install dependencies: `bundle install`
- Run server: `bundle exec rails server`
- Run console: `bundle exec rails console`
- Run all tests: `bundle exec rspec`
- Run single test: `bundle exec rspec spec/path/to/file_spec.rb:42`
- Database setup: `rails db:create db:migrate`
- Database reset: `rails db:reset`
- Test database setup: `RAILS_ENV=test rails db:test:prepare`
- With Docker: `docker-compose build && docker-compose up`

## Code Style Guidelines
- Ruby/Rails: Ruby 2.7.8, Rails 5.2.1
- Indentation: 2 spaces
- Classes: CamelCase, methods/variables: snake_case
- Models: associations → validations → callbacks → scopes → methods
- Controllers: use strong parameters, transactions for data integrity
- Views: HAML templates
- Testing: RSpec with Factory Bot, contextualized test scenarios
- Authentication: Devise + CanCanCan
- Error handling: ActiveRecord validations, rescue blocks, flash messages
- Provider scoping: Most models have provider association