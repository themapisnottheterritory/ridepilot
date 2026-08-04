class VehicleInspectionsController < ApplicationController
  
  respond_to :html, :js

  def mark_flagged
    if params[:vehicle_inspection]
      insp = VehicleInspection.find_by_id(params[:id])
      if insp
        insp.flagged = params[:vehicle_inspection][:flagged]
        insp.save(validate: false)
      end
    end

    render json: {}
  end

  def mark_mechanical
    if params[:vehicle_inspection]
      insp = VehicleInspection.find_by_id(params[:id])
      if insp
        insp.mechanical = params[:vehicle_inspection][:mechanical]
        insp.save(validate: false)
      end
    end

    render json: {}
  end

  # Sets whether an inspection item shows on the pre-trip check, the post-trip
  # check, or both. Whitelisted to the three valid phase values.
  def set_phase
    if params[:vehicle_inspection]
      insp = VehicleInspection.find_by_id(params[:id])
      if insp
        phase = params[:vehicle_inspection][:phase].to_s
        insp.phase = phase if %w[pre post both].include?(phase)
        insp.save(validate: false)
      end
    end

    render json: {}
  end
end