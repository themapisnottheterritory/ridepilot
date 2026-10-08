# POST /api/v1/fuel_logs
# Body: { fuel_log: { run_id, gallons, odometer, fueled_at, client_uuid, notes }, scan_ids: [..] }
# The tablet's "Log fuel" button (1.0.34) for fueling mid-shift. It doesn't
# touch the inspection or End run. Sending the same client_uuid again returns
# the first entry, so a retry after a dropped connection isn't a second fill.
class Api::V1::Driver::FuelLogsController < Api::V1::Driver::BaseController
  def create
    p = params.require(:fuel_log).permit(:run_id, :gallons, :odometer, :fueled_at, :client_uuid, :notes)
    if p[:client_uuid].present? && (dup = FuelLog.find_by(client_uuid: p[:client_uuid]))
      return render success_response(view(dup))
    end
    run = Run.find_by(id: p[:run_id])
    vehicle = run&.vehicle
    return render fail_response(status: 422, run: "This run has no bus, so the fuel can't be logged.") if vehicle.nil?

    log = FuelLog.new(provider_id: run.provider_id, vehicle: vehicle, run: run, driver: @driver, source: "mid_shift",
                      gallons: p[:gallons], odometer: p[:odometer].presence, notes: p[:notes].presence,
                      fueled_at: (Time.zone.parse(p[:fueled_at].to_s) rescue nil) || Time.current,
                      client_uuid: p[:client_uuid].presence)
    scans = ReadingScan.where(id: Array(params[:scan_ids]).map(&:to_i), driver_id: @driver.id, fuel_log_id: nil).to_a
    log.take_cost_from(scans.detect { |s| s.kind == "pump" })
    unless log.save
      return render fail_response(status: 422, gallons: log.errors[:gallons].any? ? "Gallons should be between 0 and #{FuelLog::MAX_GALLONS}." : log.errors.full_messages.to_sentence)
    end
    scans.each do |s|
      s.update!(fuel_log: log, accepted_value: s.kind == "odometer" ? log.odometer : log.gallons)
    end
    render success_response(view(log))
  end

  private

  def view(log)
    { id: log.id, gallons: log.gallons.to_f, odometer: log.odometer, price_per_gallon: log.price_per_gallon&.to_f,
      total_cost: log.total_cost&.to_f, fueled_at: log.fueled_at.iso8601, vehicle: log.vehicle&.name }
  end
end
