class MakeRoleFineGrained < ActiveRecord::Migration[4.2]
  def self.up
    change_table :roles do |t|
      t.integer :level
    end
    # Use execute to avoid loading the Role model which uses paranoia
    execute <<-SQL
      UPDATE roles SET level = CASE WHEN admin = true THEN 0 ELSE 100 END;
    SQL
    change_table :roles do |t|
      t.remove :admin
    end
  end

  def self.down
  end
end
