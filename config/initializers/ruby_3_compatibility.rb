# Ruby 3.x compatibility fixes for Rails 5.2
# This file patches Rails 5.2 to work with Ruby 3.2's stricter keyword argument handling

# Fix for ArgumentError: wrong number of arguments (given 3, expected 2) in add_modifier
# This occurs when PostgreSQL adapter loads with Ruby 3.x
if Rails::VERSION::MAJOR == 5 && Rails::VERSION::MINOR == 2
  module ActiveRecord
    module Type
      class AdapterSpecificRegistry
        # Patch add_modifier to handle both positional and keyword arguments
        # for Ruby 3.x compatibility
        def add_modifier(options, klass, *args, **kwargs)
          if args.empty? && kwargs.empty?
            # Called as add_modifier(options, klass)
            registrations << [options, klass]
          elsif !args.empty?
            # Called as add_modifier(options, klass, adapter)
            # Convert positional arg to keyword arg for Ruby 3.x
            adapter = args[0]
            registrations << [options.merge(adapter: adapter), klass]
          else
            # Called as add_modifier(options, klass, adapter: adapter)
            registrations << [options.merge(kwargs), klass]
          end
        end
      end
    end
  end
end
