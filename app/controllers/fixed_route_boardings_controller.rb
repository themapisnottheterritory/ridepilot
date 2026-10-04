# Dispatcher-side corrections to walk-ons on a fixed-route run (the rows are
# created by the driver tablet through api/v1/driver). Editors can fix a
# count, category or fare, or void a row; both are paper-trailed as the user.
class FixedRouteBoardingsController < ApplicationController
  load_and_authorize_resource instance_name: :boarding

  def update
    if @boarding.run.complete?
      redirect_to run_path(@boarding.run), alert: "Run is complete; set it as incomplete before correcting walk-ons."
      return
    end
    if @boarding.update(boarding_params)
      redirect_to run_path(@boarding.run), notice: "Walk-on updated."
    else
      redirect_to run_path(@boarding.run), alert: "Walk-on not updated: #{@boarding.errors.full_messages.to_sentence}"
    end
  end

  def destroy
    if @boarding.run.complete?
      redirect_to run_path(@boarding.run), alert: "Run is complete; set it as incomplete before voiding walk-ons."
      return
    end
    @boarding.destroy   # soft delete (acts_as_paranoid); the version row keeps the values
    redirect_to run_path(@boarding.run), notice: "Walk-on voided."
  end

  private

  def boarding_params
    params.require(:fixed_route_boarding).permit(:rider_category_id, :fare_type_id, :boarded_count, :alighted_count, :fare_amount)
  end

  def fixed_route_boarding_params
    boarding_params
  end
end
