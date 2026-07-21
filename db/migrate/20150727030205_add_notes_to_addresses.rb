class AddNotesToAddresses < ActiveRecord::Migration[4.2]
  def change
    add_column :addresses, :notes, :text
    change_column :translations, :value, :text rescue nil
  end
end
