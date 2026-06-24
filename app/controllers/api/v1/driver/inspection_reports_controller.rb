# DVIR step 2 — driver-facing endpoints for vehicle inspection reports.
# Auth + serialization come from Api::V1::Driver::BaseController (token auth -> @driver,
# serializer-aware success_response). Coexists with the legacy checkbox-style
# Runs#inspections / Runs#start flow.
class Api::V1::Driver::InspectionReportsController < Api::V1::Driver::BaseController

  # GET /api/v1/inspection_template?phase=pre&run_id=123
  # Returns the checklist items for the phase, scoped to the run's provider,
  # excluding cdl_only items unless the vehicle requires them.
  def template
    phase    = params[:phase].presence || "pre"
    run      = Run.find_by(id: params[:run_id])
    provider = run&.provider || @driver.provider

    items = VehicleInspection.where(provider_id: provider.id).for_phase(phase).ordered
    items = items.where(cdl_only: false) unless cdl_vehicle?(run&.vehicle)

    render success_response(items)
  end

  # GET /api/v1/inspection_reports/:id
  def show
    report = VehicleInspectionReport.find_by(id: params[:id])
    return render fail_response(status: 404, report: "Not found.") if report.nil?

    render success_response(report, include: [:run_vehicle_inspections])
  end

  # POST /api/v1/inspection_reports
  # Body: { inspection_report: { run_id, phase, odometer, lift_cycle_count, gallons,
  #         safe_to_operate, signature_data, certified_at },
  #         items: [{ vehicle_inspection_id, status, defect_note }, ...] }
  # Builds the report + line items, recomputes the defect flag, and opens a
  # maintenance event per defect. Photos upload separately via #add_photo.
  def create
    run = Run.find_by(id: report_params[:run_id])
    return render fail_response(status: 422, run: "A valid run is required.") if run.nil?

    report = VehicleInspectionReport.new(report_params.except(:run_id))
    report.assign_attributes(
      run:          run,
      provider:     run.provider || @driver.provider,
      vehicle:      run.vehicle,
      driver:       @driver,
      submitted_at: Time.current
    )

    ActiveRecord::Base.transaction do
      report.save!
      Array(params[:items]).each do |item|
        report.run_vehicle_inspections.create!(
          run:                   run,
          vehicle_inspection_id: item[:vehicle_inspection_id],
          status:                item[:status].presence || "ok",
          defect_note:           item[:defect_note]
        )
      end
      report.refresh_defects!
      report.push_defects_to_maintenance! if report.has_defects
    end

    render success_response(report.reload, include: [:run_vehicle_inspections])
  end

  # POST /api/v1/inspection_items/:id/photos   (multipart: photo=<file>)
  # Attaches a defect-evidence photo to a single line item.
  def add_photo
    item = RunVehicleInspection.find_by(id: params[:id])
    return render fail_response(status: 404, item: "Not found.") if item.nil?

    item.photos.attach(params[:photo]) if params[:photo].present?
    render success_response(id: item.id, photo_count: item.photos.count)
  end

  private

  def report_params
    params.require(:inspection_report).permit(
      :run_id, :phase, :odometer, :lift_cycle_count, :gallons,
      :safe_to_operate, :signature_data, :certified_at
    )
  end

  # Air-brake / CDL vehicle detection. A vehicle air-brake/type flag isn't wired up
  # yet (step 2 note in the seed), so default to excluding cdl_only items.
  def cdl_vehicle?(vehicle)
    return false if vehicle.nil?
    vehicle.try(:cdl_required) || false
  end
end
