# Fare card taps on a fixed-route run (docs/fare-card-design.md, phase 2).
#
#   POST /api/v1/runs/:id/token_taps   { uid, client_uuid, recorded_at, stop_id?, stop_name?, direction?,
#                                        latitude?, longitude?, offline? }
#   GET  /api/v1/runs/:id/fare_tokens  snapshot of every active token for the offline fallback
#
# A tap is one walk-on for a known rider plus, unless it is a pass or a
# transfer, a debit on their balance. The tablet shows the answer for a couple
# of seconds: green with name, category, fare and balance; red with a reason.
# Idempotent on client_uuid like the walk-on sheet, so an offline retry never
# charges twice. A tap the tablet queued offline is sent with offline: true
# and is recorded even below the floor; the office sees the negative balance.
class Api::V1::Driver::TokenTapsController < Api::V1::Driver::BaseController
  include Api::FixedRouteJson
  before_action :load_fixed_run

  def create
    return render fail_response(status: 422, run: "This run has ended.") if @run.end_odometer.present?
    uuid = params[:client_uuid].to_s.strip
    return render fail_response(status: 422, client_uuid: "client_uuid is required.") if uuid.blank?
    uid = params[:uid].to_s.strip
    return render fail_response(status: 422, uid: "Nothing was read from the card.") if uid.blank?

    stop = @run.fixed_route.stops.find_by(id: params[:stop_id]) if params[:stop_id].present?
    recorded_at = (Time.zone.parse(params[:recorded_at].to_s) rescue nil) || Time.current

    result = FareTap.new(provider: @run.provider, driver: @driver).fixed_route!(
      run: @run, uid: uid, client_uuid: uuid, recorded_at: recorded_at,
      stop: stop, stop_name: params[:stop_name].presence, direction: params[:direction].presence,
      latitude: params[:latitude].presence, longitude: params[:longitude].presence,
      offline: ActiveModel::Type::Boolean.new.cast(params[:offline]) || false
    )

    render success_response(boardings_payload(@run).merge(tap: tap_json(result)))
  rescue FareTap::UnknownToken => e
    render fail_response(status: 404, code: "unknown_token", uid: FareToken.normalize_uid(uid), tap: e.message)
  rescue FareTap::TokenNotUsable => e
    render fail_response(status: 422, code: "token_not_usable", tap: e.message, rider_name: e.token.customer&.name)
  rescue FareTap::BelowFloor => e
    render fail_response(status: 422, code: "below_floor", tap: e.message, rider_name: e.customer.name,
                         balance: e.balance.to_f, fare: e.fare.to_f)
  rescue FareTap::Error => e
    render fail_response(status: 422, code: "tap_failed", tap: e.message)
  end

  # Everything the tablet needs to give an answer while offline: who the card
  # belongs to and roughly where their balance stands. The server still has
  # the final word when the queued tap syncs.
  def index
    provider = @run.provider
    categories = RiderCategory.by_provider(provider).index_by(&:id)
    default_cat = RiderCategory.by_provider(provider).default_order.first
    tokens = FareToken.for_provider(provider.id).active.includes(:customer).to_a.select { |t| t.customer&.active }
    render success_response({
      run_id: @run.id,
      generated_at: Time.current,
      transfer_window_minutes: provider.fare_transfer_window_minutes,
      negative_floor: provider.fare_negative_floor.to_f,
      tokens: tokens.map { |t|
        cat = (t.customer.default_rider_category_id && categories[t.customer.default_rider_category_id]) || default_cat
        { uid: t.uid, serial: t.serial, kind: t.kind, rider_name: t.customer.name,
          rider_category_id: cat&.id, fare: cat&.default_fare.to_f,
          balance: t.customer.fare_balance.to_f, floor: (t.customer.fare_balance_floor || provider.fare_negative_floor).to_f,
          pass_ok: t.customer.fare_pass_active? }
      }
    })
  end

  private

  def tap_json(r)
    {
      rider_name: r.customer&.name,
      rider_category: r.category&.name,
      fare_type: r.fare_type&.name,
      fare: r.fare.to_f,
      balance: r.balance.to_f,
      transfer: !!r.transfer,
      pass: !!r.pass,
      double_tap: !!r.double_tap,
      duplicate: !!r.duplicate,
      client_uuid: r.rows.first&.client_uuid,
      submission: (r.rows.any? ? submission_json(r.rows) : nil)
    }
  end
end
