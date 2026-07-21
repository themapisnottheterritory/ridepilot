class RemoveUnnecessaryColumnsFromMonthlies < ActiveRecord::Migration[4.2]
  def self.up
    remove_column :monthlies, :end_date
    remove_column :monthlies, :complaints
    remove_column :monthlies, :compliments
  end

  def self.down
    add_column :monthlies, :end_date, :date
    add_column :monthlies, :complaints, :integer
    add_column :monthlies, :compliments, :integer
  end
end
