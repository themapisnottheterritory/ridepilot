class AddAttemptTrackingToStreetDictionaryEntries < ActiveRecord::Migration[7.1]
  # Lets the nightly rebuild skip streets that have already failed recently.
  #
  # Roughly a quarter of collected streets never resolve -- they are typos,
  # fragments ("Hwy"), or private roads the geocoder has no record of. Without
  # this, every nightly run would retry all ~2,100 of them, spending several
  # thousand geocoder requests to learn what it already knew. Retrying on a
  # long interval still picks up genuine OSM improvements, just not nightly.
  def change
    add_column :street_dictionary_entries, :last_attempted_at, :datetime
    add_column :street_dictionary_entries, :attempts, :integer, null: false, default: 0

    # The nightly scope is "unresolved and not tried lately".
    add_index :street_dictionary_entries, [:street, :last_attempted_at],
              name: 'index_street_dictionary_on_street_and_last_attempted_at'
  end
end
