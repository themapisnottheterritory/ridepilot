require "open3"

# POST /api/v1/scans   (multipart: kind=odometer|pump, run_id, photo=<file>)
# The tablet's "Scan odometer" / "Scan pump" buttons (1.0.34). Reads the photo
# with ScanReader and keeps the photo and the reading as a ReadingScan. Always
# answers 200 with whatever was read: an empty reading means "type it".
class Api::V1::Driver::ScansController < Api::V1::Driver::BaseController
  MAX_BYTES = 1_500_000      # bigger photos are shrunk before the model sees them
  ODOMETER_JUMP = 500        # miles above the last known reading that look wrong

  def create
    kind = params[:kind].to_s
    return render fail_response(status: 422, kind: "Unknown scan.") unless ReadingScan::KINDS.include?(kind)
    photo = params[:photo]
    return render fail_response(status: 422, photo: "A photo is required.") unless photo.respond_to?(:read)

    run = Run.find_by(id: params[:run_id])
    bytes, type = shrink(photo.read, photo.content_type)
    result = ScanReader.read(kind, bytes, type)

    scan = ReadingScan.create!(kind: kind, run: run, vehicle: run&.vehicle, driver: @driver,
                               provider_id: run&.provider_id || @driver.provider_id,
                               reading: result[:reading], value: result[:value], ms: result[:ms], error: result[:error])
    scan.photo.attach(io: StringIO.new(bytes), filename: "#{kind}-#{scan.id}.jpg", content_type: type)

    last = kind == "odometer" ? last_odometer(run&.vehicle) : nil
    render success_response(scan_id: scan.id, kind: kind, **result[:reading].symbolize_keys,
                            last_known_odometer: last, warning: warning(kind, result[:value], last),
                            ms: result[:ms], read: result[:value].present?)
  end

  private

  # Tablet photos run 3-5 MB; the model reads a 1600 px one just as well, faster.
  def shrink(bytes, type)
    return [bytes, type] if bytes.bytesize <= MAX_BYTES
    out, status = Open3.capture2("convert", "-", "-auto-orient", "-resize", "1600x1600>", "-quality", "85", "jpeg:-",
                                 stdin_data: bytes, binmode: true)
    status.success? && out.bytesize > 0 ? [out, "image/jpeg"] : [bytes, type]
  end

  # The bus's most recent reading, not its highest: one typo (bus 1700 has a
  # start odometer of 500,020 from the April pilot) would otherwise make every
  # later scan look wrong.
  def last_odometer(vehicle)
    return nil unless vehicle
    run = Run.where(vehicle_id: vehicle.id).where("date <= ?", Date.current)
             .where("COALESCE(end_odometer, start_odometer) > 0")
             .order(date: :desc, actual_end_time: :desc, id: :desc).first
    report = VehicleInspectionReport.where(vehicle_id: vehicle.id).where("odometer > 0").recent.first
    seen = []
    seen << [run.actual_end_time || run.date.end_of_day, run.end_odometer.to_i.positive? ? run.end_odometer : run.start_odometer] if run
    seen << [report.submitted_at, report.odometer] if report&.submitted_at
    seen.max_by(&:first)&.last
  end

  def warning(kind, value, last)
    return nil unless kind == "odometer" && value && last
    return "That's lower than this bus's last reading (#{last.to_fs(:delimited)}). Check the number." if value < last
    return "That's #{(value - last).to_fs(:delimited)} miles more than this bus's last reading (#{last.to_fs(:delimited)}). Check the number." if value - last > ODOMETER_JUMP
    nil
  end
end
