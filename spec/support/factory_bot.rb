# FactoryBot 5 changed `build` to build associations unsaved as well. The
# specs here were written against the old behaviour (associations created), and
# a built run whose driver has no id collides with every other driverless run.
FactoryBot.use_parent_strategy = false

RSpec.configure do |config|
  config.before(:suite) do
    # Transactions cover the examples; anything created outside one (before(:all),
    # aborted runs) survives to the next run, so truncate first.
    DatabaseCleaner.clean_with(:truncation)
    # Labels, buttons and validation messages come from the translation tables.
    TestTranslations.seed
  end
end
