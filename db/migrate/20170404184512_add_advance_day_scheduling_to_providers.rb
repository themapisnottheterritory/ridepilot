class AddAdvanceDaySchedulingToProviders < ActiveRecord::Migration[4.2]
  def change
    add_column :providers, :advance_day_scheduling, :integer
  end
end
