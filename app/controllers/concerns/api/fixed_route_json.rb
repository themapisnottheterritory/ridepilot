# Shared by the driver API's fixed-route controllers: loading the driver's own
# fixed run and the JSON shapes the tablet's walk-on sheet understands.
module Api::FixedRouteJson
  extend ActiveSupport::Concern

  private

  def load_fixed_run
    @run = Run.find_by(id: params[:id], driver: @driver)
    return render fail_response(status: 404, run: "Run not found.") unless @run
    return render fail_response(status: 422, run: "Not a fixed-route run.") unless @run.fixed_route? && @run.fixed_route
  end

  def route_json(route)
    { id: route.id, name: route.name, display_name: route.display_name, color: route.color, kind: route.kind }
  end

  def submission_json(rows)
    first = rows.min_by(&:id)
    {
      client_uuid: first.client_uuid,
      recorded_at: first.recorded_at,
      stop_id: first.fixed_route_stop_id,
      stop_name: first.stop_name,
      direction: first.direction,
      fare_type_id: first.fare_type_id,
      rider_name: first.customer&.name,          # set when the walk-on came from a fare card tap
      tapped: first.fare_token_id.present?,
      alighted_count: rows.sum(&:alighted_count),
      boarded_count: rows.sum(&:boarded_count),
      entries: rows.sort_by(&:id).map { |r|
        { id: r.id, rider_category_id: r.rider_category_id, rider_category: r.rider_category&.name,
          boarded_count: r.boarded_count, fare_amount: r.fare_amount&.to_f }
      }
    }
  end

  def boardings_payload(run)
    rows = run.fixed_route_boardings.includes(:rider_category, :customer).chronological.to_a
    by_uuid = rows.group_by(&:client_uuid)
    {
      run_id: run.id,
      route: route_json(run.fixed_route),
      submissions: by_uuid.values.map { |r| submission_json(r) },
      totals: {
        boarded: rows.sum(&:boarded_count),
        alighted: rows.sum(&:alighted_count),
        submissions: by_uuid.size,
        by_category: rows.group_by { |r| r.rider_category&.name }.transform_values { |r| r.sum(&:boarded_count) }
      }
    }
  end
end
