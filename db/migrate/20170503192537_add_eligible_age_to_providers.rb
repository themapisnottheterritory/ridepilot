class AddEligibleAgeToProviders < ActiveRecord::Migration[4.2]
  def change
    add_column :providers, :eligible_age, :integer
  end
end
