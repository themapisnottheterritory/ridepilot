class CreateFixedRouteTables < ActiveRecord::Migration[7.1]
  # Fixed route in RidePilot, Phase 1 / WP1 (ops/fixed-route-phase1-plan.md).
  #
  # A run gains a service mode: demand_response (everything that exists today)
  # or fixed_route. A fixed run is a route block for the day (Red, 07:00-18:00)
  # and its riders are walk-ons recorded as fixed_route_boardings rather than
  # trips. Routes and stops are synced from the fixed-route authoring tool
  # (rake fixed_routes:sync); rider categories and fare types are lookup tables.
  def change
    add_column :runs, :service_mode, :string, null: false, default: "demand_response"
    add_column :runs, :fixed_route_id, :integer
    add_index  :runs, :service_mode
    add_index  :runs, :fixed_route_id
    add_column :repeating_runs, :service_mode, :string, null: false, default: "demand_response"
    add_column :repeating_runs, :fixed_route_id, :integer
    add_index  :repeating_runs, :fixed_route_id

    create_table :fixed_routes do |t|
      t.integer  :provider_id, null: false
      t.string   :name, null: false                       # "Red", "Bay"
      t.string   :short_name                              # GTFS route_short_name, "6"
      t.string   :color                                   # hex without '#', "FF0000"
      t.string   :kind, null: false, default: "city"      # city | commuter
      t.string   :external_route_ids, array: true, default: []   # authoring-tool ids, one per direction
      t.boolean  :active, null: false, default: true
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :fixed_routes, [:provider_id, :name], unique: true, where: "deleted_at IS NULL"

    create_table :fixed_route_stops do |t|
      t.integer :fixed_route_id, null: false
      t.string  :external_route_id, null: false           # which direction's authoring-tool route
      t.string  :external_stop_id, null: false
      t.string  :direction, null: false                   # "East", "North", "Round trip"
      t.integer :sequence, null: false
      t.string  :name, null: false
      t.decimal :latitude,  precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
      t.boolean :timepoint, null: false, default: false
      t.float   :distance_along_shape_m
      t.timestamps
    end
    add_index :fixed_route_stops, [:fixed_route_id, :direction, :sequence]
    add_index :fixed_route_stops, [:fixed_route_id, :external_route_id, :external_stop_id],
              unique: true, name: "idx_fixed_route_stops_external"

    # Lookup tables (editable under Lookup Tables like Trip Purpose).
    create_table :rider_categories do |t|
      t.string   :name, null: false
      t.datetime :deleted_at
      t.timestamps
    end
    create_table :fare_types do |t|
      t.string   :name, null: false
      t.datetime :deleted_at
      t.timestamps
    end

    # One walk-on submission from the tablet becomes one row per rider category
    # with a non-zero count, all sharing client_uuid; alighted_count is stored on
    # the first row only. (client_uuid, rider_category_id) is unique so an
    # offline retry can never double-count.
    create_table :fixed_route_boardings do |t|
      t.integer  :provider_id, null: false
      t.integer  :run_id, null: false
      t.integer  :fixed_route_id
      t.integer  :fixed_route_stop_id
      t.string   :stop_name                                # snapshot, survives route edits
      t.string   :direction
      t.integer  :driver_id
      t.integer  :vehicle_id
      t.integer  :rider_category_id, null: false
      t.integer  :fare_type_id
      t.integer  :boarded_count,  null: false, default: 0
      t.integer  :alighted_count, null: false, default: 0
      t.decimal  :fare_amount, precision: 8, scale: 2
      t.datetime :recorded_at, null: false
      t.decimal  :latitude,  precision: 10, scale: 6
      t.decimal  :longitude, precision: 10, scale: 6
      t.string   :client_uuid, null: false
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :fixed_route_boardings, :run_id
    add_index :fixed_route_boardings, :recorded_at
    add_index :fixed_route_boardings, :fixed_route_id
    add_index :fixed_route_boardings, [:client_uuid, :rider_category_id], unique: true, name: "idx_fixed_route_boardings_client"
  end
end
