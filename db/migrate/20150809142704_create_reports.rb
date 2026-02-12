class CreateReports < ActiveRecord::Migration[4.2]
  def change
    create_table :custom_reports do |t|
      t.string :name

      t.timestamps
    end
  end
end
