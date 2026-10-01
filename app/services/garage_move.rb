# Moving a bus to another garage (Vehicles > a bus > Garage, 2026-10-01).
# Buses go back and forth between yards to cover runs, and each run starts
# and ends at its bus's garage unless dispatch set its own start or end.
#
# GarageMove.new(vehicle, garage, user).call:
#   - the bus now lives at `garage`
#   - its unstarted runs from today on that start or end at the bus's garage
#     (no start/end of their own, the old garage itself, or the copy of it a
#     run used to take when its bus was set) start and end at the new one;
#     a start or end dispatch set to somewhere else is left alone
#   - those runs' start and end stops move too, and a run already on a
#     tablet today is republished so the driver sees it
#   - started and past runs are untouched; the move is in the bus's history
# Returns { runs: n, republished: n }.
class GarageMove
  SAME_PLACE_METERS = 150

  # from: where the bus was, when the caller has already saved the new garage
  def initialize(vehicle, garage, user = nil, from: :current)
    @vehicle, @garage, @user = vehicle, garage, user
    @from = from
  end

  def call
    old = @from == :current ? @vehicle.garage_address : @from
    @vehicle.update_columns(garage_address_id: @garage.id)
    moved = 0
    republished = 0
    Run.where(vehicle_id: @vehicle.id).where("runs.date >= ?", Time.zone.today).where(actual_start_time: nil).find_each do |run|
      changed = false
      %i[from to].each do |end_|
        current = run.public_send("#{end_}_garage_address")
        next unless current.nil? || follows_bus?(current, old)
        run.public_send("#{end_}_garage_address_id=", @garage.id)
        changed = true
      end
      next unless changed
      run.save(validate: false)
      run.refresh_garage_stops!
      moved += 1
      if run.date == Time.zone.today && run.public_itineraries.exists?
        run.publish_manifest!(true)
        republished += 1
      end
    end
    @vehicle.create_activity :garage_moved, owner: @user,
                             params: { from: old.try(:label), to: @garage.label, runs: moved }
    { runs: moved, republished: republished }
  end

  private

  # The old garage itself, or an unnamed copy of it at the same spot
  def follows_bus?(addr, old)
    return false unless old
    return true if addr.id == old.id
    return false if addr.respond_to?(:named?) && addr.named?
    addr.the_geom && old.the_geom && addr.the_geom.distance(old.the_geom) <= SAME_PLACE_METERS
  end
end
