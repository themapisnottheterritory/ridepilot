class Api::ApiController < ActionController::Base
  protect_from_forgery prepend: true
  skip_before_action :authenticate_user!, :verify_authenticity_token, raise: false
  acts_as_token_authentication_handler_for User, fallback: :none

  # View-only tablet sign-in (TabletView): the key stands in for the driver,
  # and nothing that changes data gets through. Signing out is let through so
  # the tablet can leave; the sessions controller leaves the driver's token alone.
  before_action :authenticate_tablet_viewer
  before_action :refuse_changes_when_viewing

  protected

  def viewing_only?
    @tablet_viewer.present?
  end

  private

  def authenticate_tablet_viewer
    token = request.headers["X-USER-TOKEN"]
    return if current_user || !TabletView.key?(token)
    viewer, user = TabletView.find(token)
    return unless user && user.username == request.headers["X-USER-USERNAME"].to_s.strip.downcase
    @tablet_viewer = viewer
    request.env["devise.skip_trackable"] = true   # as the token sign-in does: viewing isn't the driver signing in
    sign_in user, store: false
    send(:after_successful_token_authentication) if respond_to?(:after_successful_token_authentication, true)
  end

  def refuse_changes_when_viewing
    return unless viewing_only?
    return if request.get? || request.head? || request.options?
    return if action_name == "destroy" && is_a?(Api::V2::SessionsController)   # sign out
    render status: 403, json: { status: "fail", data: { view_only: "View only: #{@tablet_viewer.username} is watching this tablet, so nothing can be changed." } }
  end
end
