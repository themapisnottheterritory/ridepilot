class CreateLookupTables < ActiveRecord::Migration[4.2]
  def change
    create_table :lookup_tables do |t|
      t.string :caption
      t.string :name
      t.string :value_column_name

      t.timestamps
    end
  end
end
