class CreateRunDistances < ActiveRecord::Migration[4.2]
  def change
    create_table :run_distances do |t|
      t.float :total_dist
      t.float :revenue_miles
      t.float :non_revenue_miles
      t.float :deadhead_from_garage
      t.float :deadhead_to_garage
      t.references :run

      t.timestamps
    end
  end
end
