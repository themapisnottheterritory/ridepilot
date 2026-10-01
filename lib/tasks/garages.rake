namespace :garages do
  # One-off set-up (2026-10-01): the yards each agency's buses already live at
  # become named garages, and every bus parked at one (within 300 m) is linked
  # to it through GarageMove, so its upcoming runs follow it from now on.
  # Re-runnable: existing garages are found by name, linked buses skipped.
  #   DRY=1 rake garages:seed   # say what it would do
  SEED = {
    1   => [["Victoria office", "1908 North Laurent Street", "Victoria", "77901", 28.812645, -96.989695],
            ["Port Lavaca yard", "2104 West Austin Street", "Port Lavaca", "77979", 28.600541, -96.636856],
            ["Gonzales", "1017 Water Street", "Gonzales", "78629", 29.506782, -97.459274],
            ["Edna", "404 North Kleas Street", "Edna", "77957", 28.981922, -96.645456]],
    107 => [["Goliad office", "329 W Franklin St", "Goliad", "77963", nil, nil]],
    143 => [["Hallettsville office", "310 S La Grange St", "Hallettsville", "77964", nil, nil]]
  }.freeze
  NEAR_METERS = 300

  desc "Name each agency's garages and link the buses parked at them"
  task seed: :environment do
    dry = ENV["DRY"].present?
    SEED.each do |provider_id, rows|
      rows.each do |name, street, city, zip, lat, lon|
        garage = GarageAddress.named.find_by(provider_id: provider_id, name: name)
        unless garage
          # where the agency's buses already are, if no pin was given
          lat, lon = GarageAddress.joins("JOIN vehicles v ON v.garage_address_id = addresses.id")
                                  .where("v.provider_id = ? AND lower(addresses.address) = ?", provider_id, street.downcase)
                                  .pluck(Arel.sql("ST_Y(addresses.the_geom::geometry), ST_X(addresses.the_geom::geometry)")).first unless lat
          garage = GarageAddress.new(provider_id: provider_id, name: name, address: street, city: city, state: "TX", zip: zip,
                                     the_geom: Address.compute_geom(lat, lon))
          dry ? puts("would add #{name} (#{provider_id}) at #{lat}, #{lon}") : garage.save!
        end
        next if dry && garage.new_record?
        Vehicle.where(provider_id: provider_id, active: true).where.not(garage_address_id: [nil, garage.id]).includes(:garage_address).each do |v|
          own = v.garage_address
          next unless own&.the_geom && !own.named? && own.the_geom.distance(garage.the_geom) <= NEAR_METERS
          if dry
            puts "would link #{v.name} to #{name}"
          else
            moved = GarageMove.new(v, garage, nil).call
            puts "#{v.name} -> #{name} (#{moved[:runs]} upcoming runs follow)"
          end
        end
      end
    end
  end
end
