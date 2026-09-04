# Fixed route on the driver tablet: the route's stops for the walk-on sheet,
# and the walk-ons themselves. Plain JSON, like driver_run_data.
#
#   GET    /api/v1/runs/:id/fixed_route   stops by direction + rider categories + fare types
#   GET    /api/v1/runs/:id/boardings     today's submissions + totals (rehydrate after restart)
#   POST   /api/v1/runs/:id/boardings     one walk-on submission (idempotent on client_uuid)
#   DELETE /api/v1/boardings/:client_uuid undo a whole submission (driver's own run, same day)
#
# A submission = one tap on the tablet: a stop, an alighted count, a fare
# type and one entry per rider category. It is stored as one
# fixed_route_boardings row per category with a non-zero boarded count (the
# alighted count on the first row), all sharing client_uuid.
class Api::V1::Driver::BoardingsController < Api::V1::Driver::BaseController
  before_action :load_fixed_run, except: [:destroy]

  def route
    route = @run.fixed_route
    render success_response({
      route: route_json(route),
      directions: route.directions,
      stops: route.stops.map { |s|
        { id: s.id, name: s.name, direction: s.direction, sequence: s.sequence,
          latitude: s.latitude&.to_f, longitude: s.longitude&.to_f, timepoint: s.timepoint }
      },
      rider_categories: RiderCategory.by_provider(@run.provider).default_order.map(&:as_api_json),
      fare_types: FareType.by_provider(@run.provider).default_order.map(&:as_api_json)
    })
  end

  def index
    render success_response(boardings_payload(@run))
  end

  def create
    return render fail_response(status: 422, run: "This run has ended.") if @run.end_odometer.present?

    uuid = params[:client_uuid].to_s.strip
    return render fail_response(status: 422, client_uuid: "client_uuid is required.") if uuid.blank?

    existing = @run.fixed_route_boardings.where(client_uuid: uuid)
    if existing.exists?
      # Offline retry of a submission that already landed: say so, change nothing.
      return render success_response(boardings_payload(@run).merge(submission: submission_json(existing.to_a), duplicate: true))
    end

    entries = Array(params[:entries]).map { |e| [e[:rider_category_id].to_i, e[:boarded_count].to_i, e[:fare_amount].presence&.to_f] }
                                     .select { |cat, n, _| cat > 0 && n > 0 }
    alighted = params[:alighted_count].to_i
    if entries.empty? && alighted <= 0
      return render fail_response(status: 422, entries: "Nothing to record: no riders boarded or alighted.")
    end

    categories = RiderCategory.by_provider(@run.provider).where(id: entries.map(&:first)).index_by(&:id)
    unknown = entries.map(&:first) - categories.keys
    return render fail_response(status: 422, entries: "Unknown rider category: #{unknown.join(', ')}") if unknown.any?

    stop = @run.fixed_route.stops.find_by(id: params[:stop_id]) if params[:stop_id].present?
    fare_type = FareType.by_provider(@run.provider).find_by(id: params[:fare_type_id]) if params[:fare_type_id].present?
    recorded_at = (Time.zone.parse(params[:recorded_at].to_s) rescue nil) || Time.current
    # A submission with only alighting riders still needs one row to carry the count.
    entries = [[categories.keys.first || RiderCategory.by_provider(@run.provider).default_order.first&.id, 0, nil]] if entries.empty?
    return render fail_response(status: 422, entries: "No rider categories are set up.") if entries.first.first.nil?

    rows = []
    PaperTrail.request(whodunnit: @driver.user_id.to_s) do
      FixedRouteBoarding.transaction do
        entries.each_with_index do |(cat_id, boarded, fare_amount), i|
          rows << FixedRouteBoarding.create!(
            run: @run, stop: stop, stop_name: stop&.name || params[:stop_name].presence, direction: stop&.direction || params[:direction].presence,
            rider_category_id: cat_id, fare_type: fare_type, boarded_count: boarded,
            alighted_count: (i.zero? ? alighted : 0), fare_amount: fare_amount,
            recorded_at: recorded_at, latitude: params[:latitude].presence, longitude: params[:longitude].presence,
            client_uuid: uuid
          )
        end
      end
    end

    render success_response(boardings_payload(@run).merge(submission: submission_json(rows), duplicate: false))
  rescue ActiveRecord::RecordNotUnique
    # Two retries raced; the first one won. Answer as a duplicate.
    render success_response(boardings_payload(@run).merge(submission: submission_json(@run.fixed_route_boardings.where(client_uuid: uuid).to_a), duplicate: true))
  end

  # Undo: voids every row of the submission. Only the driver's own run, only
  # today, only while the run has not ended.
  def destroy
    rows = FixedRouteBoarding.joins(:run).where(client_uuid: params[:id], runs: { driver_id: @driver.id }).to_a
    return render fail_response(status: 404, submission: "No such walk-on on your runs.") if rows.empty?
    run = rows.first.run
    return render fail_response(status: 422, run: "This run has ended.") if run.end_odometer.present?
    return render fail_response(status: 422, run: "Only today's walk-ons can be undone from the tablet.") unless run.date == Date.today

    PaperTrail.request(whodunnit: @driver.user_id.to_s) { rows.each(&:destroy) }
    render success_response(boardings_payload(run).merge(undone: params[:id]))
  end

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
      alighted_count: rows.sum(&:alighted_count),
      boarded_count: rows.sum(&:boarded_count),
      entries: rows.sort_by(&:id).map { |r|
        { id: r.id, rider_category_id: r.rider_category_id, rider_category: r.rider_category&.name,
          boarded_count: r.boarded_count, fare_amount: r.fare_amount&.to_f }
      }
    }
  end

  def boardings_payload(run)
    rows = run.fixed_route_boardings.includes(:rider_category).chronological.to_a
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
