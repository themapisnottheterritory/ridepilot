# Next Bus: a CSR on the phone with a fixed-route rider ("I'm at Mockingbird
# and Navarro, when's the next bus?"). GCRPC only (Victoria Transit). See
# NextBus, FixedRouteSchedule and LiveBuses.
class NextBusController < ApplicationController
  before_action :require_next_bus

  def index; end

  # GET /next_bus/lookup?q=mockingbird+and+navarro   or   ?lat=&lon=&label=
  def lookup
    nb = NextBus.new
    result = params[:lat].present? ? nb.at(params[:lat], params[:lon], params[:label].presence || "the map") : nb.lookup(params[:q])
    render json: present(result)
  rescue StandardError => e
    Rails.logger.error("Next Bus lookup #{params[:q].inspect}: #{e.class}: #{e.message}")
    render json: { error: "Next Bus can't reach the bus timetable right now. Try again in a minute, or ask GCRPC I.T." }, status: :service_unavailable
  end

  # GET /next_bus/map: route lines and stops, drawn once
  def map
    s = FixedRouteSchedule.current
    routes = s.routes.values.sort_by(&:sort).map do |r|
      shapes = s.trips.values.select { |t| t.route_id == r.id }.map(&:shape_id).uniq
      { id: r.id, name: r.name, color: r.color, lines: shapes.map { |id| s.shapes[id].map { |lat, lon, _| [lat.round(6), lon.round(6)] } } }
    end
    stops = s.stops.values.map { |st| { id: st.id, name: st.name, lat: st.lat, lon: st.lon } }
    fares = s.fares.map { |f| { id: f.id, price: f.price.to_f } }
    render json: { routes: routes, stops: stops, fares: fares, feed: s.feed_version }
  end

  # GET /next_bus/buses: where the buses are now, and how late
  def buses
    s = FixedRouteSchedule.current
    nb = NextBus.new
    out = LiveBuses.current.values.map do |b|
      route = s.routes[b.route_id]
      trip = s.trips.values.find { |t| t.route_id == b.route_id }
      live = trip && nb.live_for(trip)
      on_line = live && live.bus.unit == b.unit
      { unit: b.unit, route: route&.name, color: route&.color || "#1f3864", lat: b.lat, lon: b.lon, seen: b.at.strftime("%-l:%M %p"),
        on_line: !!on_line, headsign: on_line ? live.trip.headsign : nil, late_min: on_line ? (live.delay / 60.0).round : nil }
    end
    render json: out
  end

  private

  def require_next_bus
    raise CanCan::AccessDenied unless helpers.show_next_bus?
  end

  def present(result)
    clock = ->(t) { t.strftime("%-l:%M %p") }
    today = Time.zone.today
    stops = result[:stops].map do |st|
      st.merge(routes: st[:routes].map do |g|
        g.merge(buses: g[:buses].map do |b|
          day = b[:day] == today ? nil : (b[:day] == today + 1 ? "tomorrow" : b[:day].strftime("%A"))
          b.except(:at, :scheduled, :day).merge(clock: clock.(b[:at]), scheduled_clock: clock.(b[:scheduled]), day: day)
        end)
      end)
    end
    { place: result[:place], others: result[:others], stops: stops, say: result[:say] }
  end
end
