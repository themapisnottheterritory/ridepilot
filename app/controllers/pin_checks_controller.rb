# Addresses > Pins to check (Philz 2026-10-03): rider homes and saved places whose
# map pin is far from where drivers actually stop for them, learned from the bus
# GPS over several visits (DriverStops). Staff decide each one: move the pin to
# where drivers stop, or keep it. Nothing moves a pin without a person; a move can
# be undone from the same page.
class PinChecksController < ApplicationController
  def index
    @rows = DriverStops.pins_to_check([current_provider_id]).select { |r| can?(:update, r[:address]) }
    @riders = Customer.where(id: @rows.map { |r| r[:address].customer_id }.compact).index_by(&:id)
    @recent = PinCheck.where(user_id: current_user.id).or(PinCheck.where(address_id: @rows.map { |r| r[:address].id }))
                      .where("created_at >= ?", 7.days.ago).order(created_at: :desc).limit(15).includes(:address).to_a
    @seen = StopSighting.where(provider_id: current_provider_id)
    @learned_n = DriverStops.learned.size
  end

  # PATCH /pin_checks/:id (the address): decision = moved / kept
  def update
    address = Address.find(params[:id])
    authorize! :update, address
    learned = DriverStops.learned([address.id])[address.id]
    return redirect_to(pin_checks_path, alert: "Drivers' visits no longer agree on one spot for this address; nothing changed.") unless learned
    decision = params[:decision].to_s
    return redirect_to(pin_checks_path, alert: "Choose Use where drivers stop or Keep the pin.") unless PinCheck::DECISIONS.include?(decision)

    PinCheck.transaction do
      check = PinCheck.create!(address_id: address.id, decision: decision, visits: learned[:days], user_id: current_user.id,
                               from_latitude: address.latitude, from_longitude: address.longitude,
                               to_latitude: learned[:lat], to_longitude: learned[:lon])
      if decision == "moved"
        address.the_geom = Address.compute_geom(learned[:lat], learned[:lon])
        address.save!(validate: false)   # callbacks run: a rider's home re-tags their trips' area
      end
      check
    end
    redirect_to pin_checks_path, notice: decision == "moved" ? "Pin moved to where drivers stop for #{address.address}. Undo below if that was a mistake." : "Kept the pin for #{address.address}. It comes back only if drivers keep stopping somewhere else."
  end

  # DELETE /pin_checks/:id (the PinCheck): undo a move or a keep
  def destroy
    check = PinCheck.find(params[:id])
    address = Address.unscoped.find(check.address_id)
    authorize! :update, address
    if check.decision == "moved"
      unless DriverStops.meters(address.latitude, address.longitude, check.to_latitude, check.to_longitude) < 1
        return redirect_to(pin_checks_path, alert: "That pin has been changed since, so it wasn't put back.")
      end
      address.the_geom = Address.compute_geom(check.from_latitude, check.from_longitude)
      address.save!(validate: false)
    end
    check.destroy!
    redirect_to pin_checks_path, notice: "Undone: #{address.address} is back on the list with its old pin."
  end
end
