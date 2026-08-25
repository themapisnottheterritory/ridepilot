class CreateStreetDictionaryEntries < ActiveRecord::Migration[7.1]
  # Local street dictionary backing prefix completion in the address pickers.
  #
  # Nominatim matches whole tokens only -- it has no prefix index -- so typing
  # "1404 E Vir" can never match anything. The streets we serve, however, are
  # already in our own address book: ~7,700 distinct street/city pairs, which
  # IS prefix-searchable. This table holds them.
  #
  # raw_street is the local form (house number and unit stripped); street is
  # what OSM actually calls it, filled in by StreetDictionaryBuilder. The two
  # differ more often than you would expect -- local data says "206 Del Rio St"
  # where OSM has a different street type -- and feeding the local form to the
  # geocoder measurably underperforms, so completion must use the canonical
  # form. Rows where street is NULL failed to canonicalize and are excluded
  # from suggestions; they double as a data-quality worklist.
  def change
    create_table :street_dictionary_entries do |t|
      t.string   :raw_street, null: false
      t.string   :city,       null: false
      t.string   :state,      null: false, default: 'TX'
      t.string   :street
      t.string   :search_key
      t.integer  :weight,     null: false, default: 0
      t.datetime :resolved_at
      t.timestamps
    end

    # One row per distinct local street/city; the builder upserts on this.
    add_index :street_dictionary_entries, [:raw_street, :city, :state],
              unique: true, name: 'index_street_dictionary_on_raw_street_city_state'

    # Prefix matching is LIKE 'east vir%'. varchar_pattern_ops is what lets
    # Postgres use an index for that; the default opclass cannot.
    add_index :street_dictionary_entries, :search_key,
              opclass: :varchar_pattern_ops,
              name: 'index_street_dictionary_on_search_key_prefix'
  end
end
