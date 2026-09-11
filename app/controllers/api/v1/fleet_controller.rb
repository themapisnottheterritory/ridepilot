# Read-only fleet feed for the AVL side (ops/fleet-sync-plan.md).
#
#   GET /api/v1/fleet?provider_id=1        header X-Fleet-Token: <FLEET_SYNC_TOKEN>
#
# RidePilot is the source of truth for vehicles; the puller on the portal
# host pulls this hourly and upserts busavl.fleet. Nothing inbound is ever
# written. The token is a single shared secret in config/application.yml
# (FLEET_SYNC_TOKEN), separate from any user account, so it can be rotated
# without touching a login.
class Api::V1::FleetController < Api::ApiController
  skip_before_action :verify_authenticity_token, raise: false
  before_action :require_fleet_token

  def index
    provider = Provider.find_by(id: params[:provider_id]) || Provider.where(inactivated_date: nil).order(:id).first
    return render json: { status: "fail", data: { provider: "Unknown provider." } }, status: 404 unless provider

    vehicles = Vehicle.for_provider(provider.id).includes(:vehicle_type).order(:name)
    render json: {
      status: "success",
      provider: { id: provider.id, name: provider.name },
      generated_at: Time.current.iso8601,
      vehicles: vehicles.map { |v|
        {
          unit: v.name,
          make: v.make.to_s.strip.presence,
          model: v.model.to_s.strip.presence,
          year: v.year,
          vin: v.vin.presence,
          license_plate: v.license_plate.presence,
          active: v.active != false,
          seating_capacity: v.seating_capacity,
          wheelchair_lift: v.wheelchair_lift == true,
          tie_downs: v.mobility_device_accommodations,
          vehicle_type: v.vehicle_type&.name,
          accessibility_equipment: v.accessibility_equipment.presence,
          updated_at: v.updated_at&.iso8601
        }
      }
    }
  end

  private

  def require_fleet_token
    expected = ENV["FLEET_SYNC_TOKEN"].to_s
    given = request.headers["X-Fleet-Token"].to_s
    ok = expected.present? && given.present? && ActiveSupport::SecurityUtils.secure_compare(expected, given)
    render(json: { status: "fail", data: { token: "Missing or wrong X-Fleet-Token." } }, status: 401) unless ok
  end
end
