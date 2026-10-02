# The Tablets page (Philz 2026-10-02): every driver tablet's latest report from the
# Demand Response app (1.0.24+), and a light history for battery, connection and use.
class CreateTablets < ActiveRecord::Migration[5.2]
  def change
    create_table :tablets do |t|
      t.string   :android_id, null: false     # Settings.Secure.ANDROID_ID as our app sees it
      t.integer  :number                       # tablet-NN, from the WireGuard address 10.99.0.(NN+10)
      t.string   :manufacturer
      t.string   :model
      t.string   :android_version
      t.integer  :sdk
      t.string   :app_version
      t.integer  :app_code
      t.string   :username                     # who was signed in at the last report
      t.string   :last_ip
      t.jsonb    :info, null: false, default: {}   # the whole latest report
      t.text     :notes                        # technician's notes
      t.datetime :first_seen_at
      t.datetime :last_seen_at
      t.timestamps
    end
    add_index :tablets, :android_id, unique: true
    add_index :tablets, :number

    create_table :tablet_pings do |t|
      t.references :tablet, null: false, index: false
      t.datetime :at, null: false
      t.integer  :battery
      t.boolean  :charging
      t.string   :network        # wifi / cell / none
      t.boolean  :vpn
      t.string   :connection     # the app's own verdict: ok / offline / vpn_off / unreachable
      t.string   :app_version
      t.string   :username
      t.integer  :storage_free_mb
    end
    add_index :tablet_pings, [:tablet_id, :at]
  end
end
