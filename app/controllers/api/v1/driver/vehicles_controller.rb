class Api::V1::Driver::VehiclesController < Api::V1::Driver::BaseController
  # The active fleet for the driver's provider, so the tablet can offer the
  # unit list when the driver is not in the vehicle dispatch assigned.
  def index
    vehicles = Vehicle.for_provider(@driver.provider_id).where(active: true).default_order
    render success_response(vehicles)
  end
end
