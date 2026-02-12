begin
  require 'translation_engine'
rescue LoadError => e
  # Create a stub TranslationEngine module if the gem can't be loaded
  module TranslationEngine
    def self.available_locales
      [:en]
    end

    class Engine < Rails::Engine
      isolate_namespace TranslationEngine
    end
  end
end