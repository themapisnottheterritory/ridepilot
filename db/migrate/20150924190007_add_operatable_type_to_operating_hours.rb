class AddOperatableTypeToOperatingHours < ActiveRecord::Migration[4.2]
  def change
    add_column :operating_hours, :operatable_type, :string
  end
end
