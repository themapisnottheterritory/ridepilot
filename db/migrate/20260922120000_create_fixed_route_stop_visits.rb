class CreateFixedRouteStopVisits < ActiveRecord::Migration[7.1]
  # Which published stops a fixed-route bus actually stopped at. The tablet
  # (GCRPC Fixed Route) watches its own position: a stop is *served* when the
  # bus comes to rest within a bus length of it, *skipped* when the bus passes
  # it without stopping. One row per stop per trip, posted in batches and
  # idempotent on client_uuid, so the office can see skipped stops and dwell
  # times per run, and a compliance report can be built on top.
  def change
    create_table :fixed_route_stop_visits do |t|
      t.integer  :provider_id,          null: false
      t.integer  :run_id,               null: false
      t.integer  :fixed_route_id
      t.integer  :fixed_route_stop_id
      t.string   :external_route_id,    null: false   # GTFS/tool route id, e.g. fy2027-blue-north
      t.string   :external_stop_id,     null: false
      t.string   :trip_id                              # the tool's run id within the route, e.g. run_03
      t.string   :stop_name
      t.string   :direction
      t.integer  :sequence
      t.string   :status,               null: false   # served | skipped
      t.time     :scheduled_time                       # published time at this stop for this trip, if any
      t.datetime :arrived_at
      t.datetime :departed_at
      t.integer  :dwell_seconds
      t.integer  :deviation_seconds                    # departed (or passed) minus scheduled; negative = early
      t.decimal  :latitude,  precision: 10, scale: 6
      t.decimal  :longitude, precision: 10, scale: 6
      t.string   :client_uuid,          null: false
      t.timestamps
    end
    add_index :fixed_route_stop_visits, :client_uuid, unique: true
    add_index :fixed_route_stop_visits, [:run_id, :trip_id, :sequence]
    add_index :fixed_route_stop_visits, [:provider_id, :created_at]
  end
end
