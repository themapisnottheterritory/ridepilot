class ClientPortalController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :get_providers
  before_action :authenticate_via_token

  layout "client_portal"

  def show
    @upcoming_trips = @current_customer.trips
                                       .where("pickup_time > ?", Time.current)
                                       .where.not(run_id: nil)
                                       .order(:pickup_time)
                                       .limit(3)
                                       .includes(:run, :pickup_address, :dropoff_address)
    @next_trip = @upcoming_trips.first
  end

  def offline
    render layout: false
  end

  private

  def authenticate_via_token
    token = params[:token] || session[:client_token]
    customer_auth = CustomerAuth.active.find_by(token: token)

    if customer_auth
      session[:client_token] = token
      @current_customer = customer_auth.customer
    else
      render plain: "Link expired. Please call us for a new link.", status: :unauthorized
    end
  end
end
