# A place a run starts or ends. Two kinds (2026-10-01):
#
#  - a named garage ("Port Lavaca yard"): one record per yard, shared by every
#    bus that lives there and by the runs that start or end there, so moving a
#    bus is a pick from a list (GarageMove) and fixing a yard's pin fixes it
#    for all of them. Fleet adds them on Vehicles > Garages; the name is unique
#    within the agency and the pin must be in the service area.
#  - an unnamed one: a bus's own address, or a run's one-off start or end
#    (the copies RidePilot used to make of every bus's garage).
class GarageAddress < Address
  validates :the_geom, presence: { message: "isn't on the map: pick the address from the list that comes up as you type" }
  validate :name_unique_in_agency, if: :named?

  scope :named, -> { where.not(name: [nil, ""]).where(customer_id: nil) }
  scope :usable, -> { where("coalesce(addresses.inactive, false) = false") }

  def named?
    name.present?
  end

  # What a run takes as its start or end from this garage: a named garage
  # itself, so the run follows the yard; a bus's own address as a copy, as
  # before. Copying a named garage made another garage of the same name each
  # time a run was created or closed (23 "Victoria office" on the Garages
  # list by 2026-10-06).
  def for_run
    named? ? self : dup
  end

  def label
    named? ? "#{name} (#{[address, city].compact.join(', ')})" : [address, city].compact.join(", ")
  end

  # Buses that live here, and unstarted runs from today on that start or end
  # here, directly or through their bus.
  def vehicles
    Vehicle.where(garage_address_id: id)
  end

  def upcoming_runs
    Run.where("runs.date >= ?", Time.zone.today).where(actual_start_time: nil)
       .where("from_garage_address_id = :id OR to_garage_address_id = :id OR " \
              "((from_garage_address_id IS NULL OR to_garage_address_id IS NULL) AND vehicle_id IN (:vehicles))",
              id: id, vehicles: vehicles.select(:id))
  end

  def in_use?
    vehicles.where(active: true).exists? || upcoming_runs.exists?
  end

  # A named garage still used by a bus or an upcoming run can't be retired.
  def retire!
    return false if in_use?
    update_column(:inactive, true)
  end

  private

  def name_unique_in_agency
    clash = GarageAddress.named.where(provider_id: provider_id).where("lower(addresses.name) = ?", name.strip.downcase)
    clash = clash.where.not(id: id) if persisted?
    errors.add(:name, "is already used by another garage") if clash.exists?
  end
end
