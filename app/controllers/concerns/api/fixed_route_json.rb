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

  # Where a walk-on or a tap happened, and which route gets the ridership.
  # stop_id is a row of the run's own route: the ordinary case. When one bus
  # drives several routes back to back (a block -- the tablet is on Green while
  # the RidePilot run is Gold's), the run's route has none of the stops the
  # tablet is passing, so it sends the authoring tool's route and stop ids
  # instead and the stop is looked up across the provider's routes. The
  # boarding is then credited to the route the stop belongs to, not the run's,
  # so route ridership stays right on the days one driver covers two routes.
  # A combo run (Gold+Green) has no stops of its own; its operating stops are
  # its parts' rows, so the stop found is Gold's or Green's either way.
  def resolve_boarding_stop
    stop = @run.fixed_route.operating_stops.find_by(id: params[:stop_id]) if params[:stop_id].present?
    ext_route = params[:external_route_id].to_s.strip
    ext_stop  = params[:external_stop_id].to_s.strip
    if stop.nil? && ext_route.present? && ext_stop.present?
      stop = FixedRouteStop.joins(:fixed_route)
                           .where(fixed_routes: { provider_id: @run.provider_id, deleted_at: nil })
                           .find_by(external_route_id: ext_route, external_stop_id: ext_stop)
    end
    route = stop&.fixed_route
    # A combo route (Gold+Green) lists its parts' route ids too; credit the part.
    route ||= FixedRoute.for_provider(@run.provider_id).active.where("? = ANY(external_route_ids)", ext_route)
                        .order(Arel.sql("cardinality(external_route_ids)")).first if ext_route.present?
    [stop, route || @run.fixed_route]
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
