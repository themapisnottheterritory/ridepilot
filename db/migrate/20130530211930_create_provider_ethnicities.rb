class CreateProviderEthnicities < ActiveRecord::Migration[4.2]
  def self.up
    create_table :provider_ethnicities do |t|
      t.integer :provider_id
      t.string :name

      t.timestamps
    end
  end

  def self.down
    drop_table :provider_ethnicities
  end
end
