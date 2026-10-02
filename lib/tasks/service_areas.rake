namespace :service_areas do
  # Census boundaries (TIGERweb, current: State_County layer 1, Incorporated Places layer 4),
  # saved in db/data/service_areas so nothing is fetched at run time. ServiceArea.
  desc "Load the county and Victoria city boundaries used to tag trips by area"
  task load: :environment do
    conn = ActiveRecord::Base.connection
    # neighbor_counties: only to name the county of an out-of-area home ("Out of area: Lavaca County")
    [["county", "counties.geojson"], ["county", "neighbor_counties.geojson"], ["city", "victoria_city.geojson"]].each do |kind, file|
      JSON.parse(File.read(Rails.root.join("db", "data", "service_areas", file)))["features"].each do |f|
        name = f["properties"]["BASENAME"]
        # PostgreSQL 9.4 here: no ON CONFLICT, so replace the row
        conn.execute(ActiveRecord::Base.sanitize_sql_array(["delete from service_area_boundaries where kind = ? and name = ?", kind, name]))
        conn.execute(ActiveRecord::Base.sanitize_sql_array([<<~SQL, kind, name, f["properties"]["GEOID"], f["geometry"].to_json]))
          insert into service_area_boundaries (kind, name, geoid, geom, created_at, updated_at)
          values (?, ?, ?, ST_Multi(ST_SetSRID(ST_GeomFromGeoJSON(?), 4326)), now(), now())
        SQL
        puts "#{kind} #{name}"
      end
    end
  end

  desc "Tag GCRPC trips from today on with the rider's area (ServiceArea)"
  task tag_upcoming: :environment do
    n = 0
    Customer.where(id: Trip.where(provider_id: ServiceArea::PROVIDER_ID).where("pickup_time >= ?", Time.zone.today.beginning_of_day).select(:customer_id)).find_each do |c|
      n += ServiceArea.retag_upcoming!(c)
    end
    puts "tagged #{n} trips"
  end
end
