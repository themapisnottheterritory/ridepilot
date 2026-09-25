class UsersEmailUniqueOnlyWhenNotDeleted < ActiveRecord::Migration[7.1]
  # User soft-deletes (acts_as_paranoid), but index_users_on_email was a plain
  # unique index, so a deleted user still owned its email and re-creating that
  # person (e.g. after moving them to another provider) failed with a
  # PG::UniqueViolation. The model validation already scopes uniqueness to
  # deleted_at IS NULL; the index now matches it. Hit 2026-09-25 with the
  # Lavaca County staff accounts.
  def up
    remove_index :users, name: "index_users_on_email"
    add_index :users, :email, unique: true, where: "deleted_at IS NULL", name: "index_users_on_email"
  end

  def down
    remove_index :users, name: "index_users_on_email"
    add_index :users, :email, unique: true, name: "index_users_on_email"
  end
end
