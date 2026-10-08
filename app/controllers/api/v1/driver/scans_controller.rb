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

  def last_odometer(vehicle)
    return nil unless vehicle
    runs = Run.where(vehicle_id: vehicle.id).where("date <= ?", Date.current)
    [runs.maximum(:end_odometer), runs.maximum(:start_odometer),
     VehicleInspectionReport.where(vehicle_id: vehicle.id).maximum(:odometer)].compact.max
  end

  def warning(kind, value, last)
    return nil unless kind == "odometer" && value && last
    return "That's lower than this bus's last reading (#{last}). Check the number." if value < last
    return "That's #{value - last} miles more than this bus's last reading (#{last}). Check the number." if value - last > ODOMETER_JUMP
    nil
  end
end
