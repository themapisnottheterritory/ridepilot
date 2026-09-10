class CreateFareTokensAndTransactions < ActiveRecord::Migration[7.1]
  # Fare cards, phase 1 (docs/fare-card-design.md).
  #
  # Account-based: a rider's balance lives on the customer, not on the card.
  # A fare_token is anything that identifies the customer at the door -- an
  # RFID card's factory UID, a printed QR code, later maybe a bank-card
  # reference -- and fare_transactions is an append-only ledger of loads,
  # debits, refunds and adjustments. customers.fare_balance caches the sum.
  #
  # The old fare_cards / fare_card_data tables (card -> customer, plus an
  # empty tap log) came from a 2023 prototype and were never wired to any
  # model. Production holds six rows, all for test customers. They are
  # dropped here; ops/git-hooks/pre-commit no longer lists them.
  def up
    drop_table :fare_card_data, if_exists: true
    drop_table :fare_cards, if_exists: true

    create_table :fare_tokens do |t|
      t.integer  :provider_id, null: false
      t.integer  :customer_id, null: false
      t.string   :kind, null: false, default: "rfid"      # rfid | qr | bank_card_ref
      t.string   :uid, null: false                        # canonical: stripped, upcased; what the reader types
      t.string   :serial                                  # short number printed on the card face
      t.string   :status, null: false, default: "active"  # active | lost | blocked | retired
      t.string   :note
      t.datetime :issued_at
      t.integer  :issued_by_user_id
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :fare_tokens, :uid, unique: true, where: "deleted_at IS NULL"
    add_index :fare_tokens, [:provider_id, :serial], unique: true, where: "deleted_at IS NULL AND serial IS NOT NULL"
    add_index :fare_tokens, :customer_id

    # Append only: rows are never updated or deleted, so no updated_at and no
    # deleted_at. A mistake is corrected by a further adjust / refund row.
    create_table :fare_transactions do |t|
      t.integer  :provider_id, null: false
      t.integer  :customer_id, null: false
      t.integer  :fare_token_id
      t.string   :kind, null: false                       # load | debit | refund | adjust | transfer_in | transfer_out
      t.decimal  :amount, precision: 8, scale: 2, null: false        # signed: + adds to the balance, - takes from it
      t.decimal  :balance_after, precision: 8, scale: 2, null: false
      t.string   :payment_method                          # loads only: cash | check | card_online
      t.string   :reference                               # check number, receipt number, processor id
      t.string   :note
      t.integer  :run_id
      t.integer  :trip_id
      t.integer  :fixed_route_boarding_id
      t.integer  :recorded_by_user_id
      t.integer  :driver_id
      t.string   :client_uuid, null: false                # idempotent retries from the tablet
      t.datetime :recorded_at, null: false
      t.datetime :created_at, null: false
    end
    add_index :fare_transactions, :client_uuid, unique: true
    add_index :fare_transactions, [:customer_id, :recorded_at]
    add_index :fare_transactions, [:provider_id, :recorded_at]
    add_index :fare_transactions, :trip_id
    add_index :fare_transactions, :fixed_route_boarding_id

    add_column :customers, :fare_balance, :decimal, precision: 8, scale: 2, null: false, default: 0
    add_column :customers, :fare_balance_floor, :decimal, precision: 8, scale: 2   # per-customer override of the provider floor
    add_column :customers, :fare_pass_expires_on, :date                            # unlimited pass: no debit while valid
    add_column :customers, :default_rider_category_id, :integer                    # drives the fixed-route fare on a tap

    add_column :providers, :fare_negative_floor, :decimal, precision: 6, scale: 2, null: false, default: 0
    add_column :providers, :fare_transfer_window_minutes, :integer, null: false, default: 90

    # A "Card" fare type so fixed-route reports separate card boardings from
    # cash and pass. fare_factor 1.0: the fare is collected, from the balance.
    execute <<~SQL
      INSERT INTO fare_types (name, fare_factor, created_at, updated_at)
      SELECT 'Card', 1.0, now(), now()
      WHERE NOT EXISTS (SELECT 1 FROM fare_types WHERE lower(name) = 'card' AND deleted_at IS NULL)
    SQL
  end

  def down
    remove_column :providers, :fare_transfer_window_minutes
    remove_column :providers, :fare_negative_floor
    remove_column :customers, :default_rider_category_id
    remove_column :customers, :fare_pass_expires_on
    remove_column :customers, :fare_balance_floor
    remove_column :customers, :fare_balance
    drop_table :fare_transactions
    drop_table :fare_tokens
    # fare_cards / fare_card_data are not recreated; they held only test rows.
  end
end
