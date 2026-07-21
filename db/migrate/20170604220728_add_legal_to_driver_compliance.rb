class AddLegalToDriverCompliance < ActiveRecord::Migration[4.2]
  def change
    add_column :driver_compliances, :legal, :boolean
  end
end
