# POST /api/v1/tablet_report -- the Demand Response app (1.0.24+) describing its
# tablet (TabletReportService in the app; Tablet.record!). Works before anyone
# signs in, so it takes no sign-in, but only from the tablets' networks: the
# WireGuard tunnel (10.99.0.x) and the office LAN.
class Api::V1::TabletReportsController < Api::ApiController
  ALLOWED = [IPAddr.new("10.99.0.0/24"), IPAddr.new("10.0.0.0/24"), IPAddr.new("192.168.1.0/24"), IPAddr.new("127.0.0.0/8")].freeze

  skip_before_action :refuse_changes_when_viewing   # a view-only tablet still describes itself

  def create
    ip = request.remote_ip
    return head(:forbidden) unless ALLOWED.any? { |net| net.include?(ip) rescue false }
    report = params.require(:report).permit!.to_h
    app = (params[:app] || {}).permit!.to_h
    app["username"] = current_user.username if current_user && !viewing_only?   # the token says who, when there is one
    tablet = Tablet.record!(report: report, app: app, ip: ip)
    wanted = tablet.update_wanted?(app["name"])
    tablet.settle_update_request!
    # update: GCRPC I.T. asked this tablet to update (Tablets page) and this app is behind
    render json: { tablet: tablet.label, update: wanted }
  rescue ArgumentError, ActionController::ParameterMissing => e
    render status: 422, json: { error: e.message }
  end
end
