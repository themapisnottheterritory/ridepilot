class Api::V1::Driver::DriverSessionsController < Api::V2::SessionsController
  skip_before_action :require_authentication, only: [:create]

  # Signs in an existing driver, returning auth token
  # POST /driver_sign_in
  def create
    validate_user

    if @errors.empty?
      @driver = Driver.find_by(user_id: @user.id)
      unless @driver.present?
        @fail_status = 401
        @errors[:username] = "User is not a driver."
      end
    end

    if @errors.empty?
      # The session goes out twice: under data (this API's shape, which the
      # Demand Response app reads) and at the top level, where the fixed-route
      # tablet (GCRPC Fixed Route 1.9-1.12) looks for it. Without the second
      # copy every fixed-route sign-in failed with "Sign-in failed (200)"
      # (Andrew, 2026-09-30).
      response = success_response(message: "Driver Signed In Successfully", session: session_hash)
      response[:json][:session] = session_hash
      render(response) and return
    else
      render(fail_response(errors: @errors, status: @fail_status))
    end
  end

  private

  # A view-only sign-in (TabletView) gets its own key, never the driver's
  # token, and a name that says so on the tablet.
  def session_hash
    {
      id: @user.id,
      driver_id: @driver.id,
      provider_id: @driver.provider_id,
      name: @view_token ? "#{@user.name} (view only)" : @user.name,
      username: @user.username,
      authentication_token: @view_token || @user.authentication_token,
      view_only: @view_token.present?
    }
  end
end
