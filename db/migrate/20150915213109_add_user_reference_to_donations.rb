class AddUserReferenceToDonations < ActiveRecord::Migration[4.2]
  def change
    add_reference :donations, :user, index: true
  end
end
