# Stops a driver's tablet has been shown (CreateManifestSeenStops). The driver
# manifest API notes what it sends for today's runs, and sends back, as
# "withdrawn", any stop it sent earlier that is no longer on the manifest, with
# why, so the tablet crosses it out instead of dropping it. A stop is its trip
# and leg, not its itinerary row: a re-publish rebuilds itineraries.
class ManifestSeenStop < ApplicationRecord
  belongs_to :run

  # Why a stop left the run, as [cause, label]. The tablet colours by cause.
  CAUSES = {
    "CANC" => "cancelled", "LTCANC" => "cancelled", "SDCANC" => "cancelled",
    "NS" => "no_show", "MT" => "missed", "TD" => "removed", "UNMET" => "removed"
  }.freeze

  def self.key(itin)
    [itin.trip_id, itin.leg_flag]
  end

  def self.revenue?(itin)
    itin.trip_id && [1, 2].include?(itin.leg_flag)
  end

  # Remember the stops in `itins` (already being sent) for this run.
  def self.note!(run, itins)
    seen = where(run_id: run.id).pluck(:trip_id, :leg_flag).to_set
    itins.each do |itin|
      next unless revenue?(itin) && !seen.include?(key(itin))
      address = itin.address
      begin
        create!(run_id: run.id, trip_id: itin.trip_id, leg_flag: itin.leg_flag, itinerary_id: itin.id,
                customer_name: itin.trip&.customer&.name, address_text: address&.one_line_text,
                time: itin.time || itin.public_itinerary&.eta)
      rescue ActiveRecord::RecordNotUnique
        # two requests at once: the other one noted it
      end
    end
  end

  # Stops shown before that aren't in `itins` now, with why, for the tablet.
  def self.withdrawn(run, itins)
    now = itins.select { |i| revenue?(i) }.map { |i| key(i) }.to_set
    gone = where(run_id: run.id).order(:time, :id).reject { |s| now.include?([s.trip_id, s.leg_flag]) }
    trips = Trip.with_deleted.includes(:trip_result, :run).where(id: gone.map(&:trip_id)).index_by(&:id)
    gone.map do |s|
      cause, label = cause_for(trips[s.trip_id], run)
      { trip_id: s.trip_id, leg_flag: s.leg_flag, itinerary_id: s.itinerary_id, customer_name: s.customer_name,
        address_text: s.address_text, time: s.time&.iso8601, cause: cause, reason: label }
    end
  end

  def self.cause_for(trip, run)
    return ["removed", "Taken off your run"] if trip.nil? || trip.deleted_at
    result = trip.trip_result
    return [CAUSES[result.code], result.name] if result && CAUSES[result.code]
    return ["moved", "Moved to #{trip.run.name}"] if trip.run && trip.run_id != run.id
    ["removed", "Taken off your run"]
  end
end
