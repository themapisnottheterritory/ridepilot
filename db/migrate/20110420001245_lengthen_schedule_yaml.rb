class LengthenScheduleYaml < ActiveRecord::Migration[4.2]
  def self.up
    change_column(:repeating_trips, :schedule_yaml, :text)
  end

  def self.down
    change_column(:repeating_trips, :schedule_yaml, :string)
  end
end
