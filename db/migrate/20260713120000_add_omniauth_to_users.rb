class AddOmniauthToUsers < ActiveRecord::Migration[7.1]
  # Phase 1 (dark) of the Office 365 / Entra ID SSO migration.
  # Links a RidePilot User to their Entra identity. omniauth_uid stores the
  # Azure immutable object id ("oid" claim) so the link survives email/name
  # changes. Named omniauth_* to avoid confusion with the Provider tenant
  # model and users.current_provider_id. No data change to existing rows.
  def change
    add_column :users, :omniauth_provider, :string
    add_column :users, :omniauth_uid, :string

    # Partial unique index: many users may have NULLs; the pair is unique only
    # once linked. (Postgres treats NULLs as distinct, but the partial index
    # makes the intent explicit.)
    add_index :users, [:omniauth_provider, :omniauth_uid],
              unique: true,
              where: "omniauth_provider IS NOT NULL AND omniauth_uid IS NOT NULL",
              name: "index_users_on_omniauth_provider_and_uid"
  end
end
